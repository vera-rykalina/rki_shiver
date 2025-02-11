nextflow.enable.dsl = 2

// Change is required! Specify your projectDir here
projectDir = "/home/rykalinav/scratch/rki_recency/Pipeline"


// ********************** NEXTFLOW RUN **************************
// Activate nextflow environment
// cd to Pipeline folder and then type:
// nextflow run /Scripts/shiver_pipeline.nf \
// -c Scripts/rki_profile.config \
// -profile rki_slurm,rki_mamba \
// --outdir ConsensusComparison \
// -with-report HTML/report_$(date +%T).html
// # use this paramete to build a flowchart
// -with-dag pipeline_flowchart.png (pipeline_flowchart.mmd)
// # use this parameter for an empty test run
// -stub


// Parameters for kraken2
params.krakendb = "/scratch/databases/kraken2_20230314/"

// Parameters for shiver
params.trimmomatic = "${projectDir}/Scripts/bin/trimmomatic-0.36.jar"
params.gal_primers = "${projectDir}/DataShiverInit/primers_GallEtAl2012.fasta"
params.sk_primers = "${projectDir}/DataShiverInit/primers_sk.fasta"
params.illumina_adapters = "${projectDir}/DataShiverInit/adapters_Illumina.fasta"
params.alignment = "${projectDir}/DataShiverInit/HIV1_COM_2012_genome_DNA_NoGaplessCols.fasta"
params.remove_whitespace = "${projectDir}/Scripts/bin/tools/RemoveTrailingWhitespace.py"
params.config_CO20 = "${projectDir}/Scripts/bin/config_CO20.sh"
params.config = "${projectDir}/Scripts/bin/config.sh"

params.outdir = null
if (!params.outdir) {
  println "outdir: $params.outdir"
  error "Missing output directory!"
}


log.info """
====================================================
       FL to FRAGMENT FASTQ FILTER PIPELINE
====================================================
             Author: Vera Rykalina
       Affiliation: Robert Koch Institute 
              Created: 27 July 2023
         Last Updated: 31 Oktober 2024
====================================================
         """

// KRAKEN2
process KRAKEN2_CLASSIFY {

    label "kraken2"
    conda "${projectDir}/Environments/kraken2.yml"
    publishDir "${params.outdir}/00_kraken_report/${id}", pattern: "*.txt", mode: "copy", overwrite: true

    // SLURM cluster options
    // cpus 10,  memory "150 GB", time "4h"
    // clusterOptions "--job-name=classify_${sample}"
    //tag "${id}_kraken2_classify"

    input:
        tuple val(id), path(reads)
        val (db)

    output:
        tuple val(id), path("${id}.classified.R*.fastq"),     emit: fastq
        tuple val(id), path("${id}.kraken.out.txt"),          emit: kraken_output
        tuple val(id), path("${id}.kraken.report.txt"),       emit: kraken_report
  
 script:
        """
            kraken2 \
                --threads 10 \
                --db ${db} \
                --paired \
                --classified-out ${id}.classified.R#.fastq \
                --output ${id}.kraken.out.txt \
                --report ${id}.kraken.report.txt \
                ${reads[0]} ${reads[1]}
        """
}

// SHIVER PART (including IVA and KALLISTO)
process INITIALISATION {
  //conda "/home/beast2/anaconda3/envs/shiver"
  conda "${projectDir}/Environments/shiver.yml"
  publishDir "${projectDir}/${params.outdir}/01_init_dir", mode: "copy", overwrite: true

  input:
     
  output:
     path "InitDir", emit: InitDir
     path "InitDir/ExistingRefsUngapped.fasta", emit: ExistingRefsUngapped
     path "InitDir/IndividualRefs/*.fasta", emit: IndividualRefs
  script:
  
  """
  shiver_init.sh \
    InitDir \
    ${params.config} \
    ${params.alignment} \
    ${params.illumina_adapters} \
    ${params.gal_primers}
  """  
}

process FASTQ_ID_HEADER {
  //conda "/home/beast2/anaconda3/envs/shiver"
  conda "${projectDir}/Environments/shiver.yml"
  //publishDir "${params.outdir}/N_id_fastq", mode: "copy", overwrite: true
  debug true

  input:
    tuple val(id), path(reads)
  output:
    // RWS - removed white space (change fastq header here as well)
    tuple val("${id}"), path("${reads[0].getBaseName().split("_R")[0]}_RWS_1.fastq"), path("${reads[1].getBaseName().split("_R")[0]}_RWS_2.fastq")
  
  script:
   """
   zcat ${reads[0]} |\
      awk '{if (NR%4 == 1) {print \$1 "/" \$2} else print}' |\
      sed 's/:N:.*//' > ${reads[0].getBaseName().split("_R")[0]}_1.fastq
   rm ${reads[0]}

   python \
     ${params.remove_whitespace} \
     ${reads[0].getBaseName().split("_R")[0]}_1.fastq > ${reads[0].getBaseName().split("_R")[0]}_RWS_1.fastq

   zcat ${reads[1]} |\
      awk '{if (NR%4 == 1) {print \$1 "/" \$2} else print}' |\
      sed 's/:N:.*//' > ${reads[1].getBaseName().split("_R")[0]}_2.fastq
   rm ${reads[1]}
   
   python \
     ${params.remove_whitespace} \
     ${reads[0].getBaseName().split("_R")[0]}_2.fastq > ${reads[0].getBaseName().split("_R")[0]}_RWS_2.fastq
   """
}

process KALLISTO_INDEX {
  //conda "/home/beast2/anaconda3/envs/kalisto"
  conda "${projectDir}/Environments/kallisto.yml"
  publishDir "${projectDir}/${params.outdir}/02_kallisto_idx", mode: "copy", overwrite: true

  input:
     path fasta
  
  output:
     path "*.idx"
 
  script:
  """
  kallisto index --index ExistingRefsUngapped.idx ${fasta}
  """
}

process KALLISTO_QUANT {
  //conda "/home/beast2/anaconda3/envs/kalisto"
  conda "${projectDir}/Environments/kallisto.yml"
  publishDir "${projectDir}/${params.outdir}/03_kallisto_quant", mode: "copy", overwrite: true
  debug true

  input:
     tuple path(index), val(id), path(reads)

  output:
     tuple val(id), path("${id}/${id}_abundance.tsv")
   
  script:
   """
   kallisto quant \
    -i ${index} \
    -o ${id} \
    --plaintext ${reads[0]} ${reads[1]}

    mv ${id}/abundance.tsv ${id}/${id}_abundance.tsv
  """
}

process BEST_ALIGNMENT {
  publishDir "${projectDir}/${params.outdir}/04_best_ref", mode: "copy", overwrite: true
  debug true

  input:
     path alignments
     tuple val(id), path(abundancetsv)

  output:
     tuple val(id), path("${id}_bestRef.fasta")
   
  script:
   """
   BestRef=\$(sort -k5 -g ${abundancetsv} | tail -n1 | cut -f1)
   echo "Sample ID: " ${id} "\nBest Kallisto Reference: " \${BestRef} 
   mv \${BestRef}.fasta  ${id}_bestRef.fasta
   """
}

process IVA_CONTIGS {
  label "iva"
  //conda "/home/beast2/anaconda3/envs/iva"
  conda "${projectDir}/Environments/iva.yml"
  publishDir "${params.outdir}/05_iva_contigs", mode: "copy", overwrite: true
  errorStrategy "retry"

  input:
    tuple val(id), path(reads)

  output:
    tuple val("${id}"), path("${id}/${id}_contigs.fasta")

  script:
    """
    iva \
      -f ${reads[0]} \
      -r ${reads[1]} \
      --threads 16 \
      --pcr_primers ${params.gal_primers} \
      --adapters ${params.illumina_adapters} \
      --trimmomatic ${params.trimmomatic} \
      ${id} || mkdir -p ${id} && touch ${id}/contigs.fasta


    mv ${id}/contigs.fasta ${id}/${id}_contigs.fasta
    """
}

process ALIGN_CONTIGS {
  //conda "/home/beast2/anaconda3/envs/shiver"
  conda "${projectDir}/Environments/shiver.yml"
  publishDir "${params.outdir}/06_alignments/${id}", mode: "copy", overwrite: true
  //debug true
  
  input:
    path initdir
    tuple val(id), path(contigs)

  output:
    tuple val("${id}"), path("${id}_wRefs.fasta"), path("${id}.blast")

  script:
    if ( contigs.size() > 0 ) {
    """
    shiver_align_contigs.sh \
      ${initdir} \
      ${params.config} \
      ${contigs} \
      ${id}

    rm temp_*
    rm *_MergedHits.blast*
    mv ${id}_cut_wRefs.fasta ${id}_wRefs.fasta || mv ${id}_raw_wRefs.fasta ${id}_wRefs.fasta 
    """
  } else {
    """
     printf "There is no contig for sample with ID: ${id}"
     touch ${id}.blast
     touch ${id}_wRefs.fasta
    """
  }
}

process MAP {
  //conda "/home/beast2/anaconda3/envs/shiver"
  conda "${projectDir}/Environments/shiver.yml"
  publishDir "${params.outdir}/07_mapped/${id}", mode: "copy", overwrite: true
  //debug true

  input:
    path initdir
    tuple val(id), path(kallistoRef), path(read1), path(read2), path(contigs), path(shiverRef), path(blast)
  
  output:
    tuple val("${id}"), path("${id}*ref.fasta"), path("${id}*.bam"), path("${id}*.bam.bai"), path("${id}*WithHXB2.csv")
    
  script:
    if ( shiverRef.size() > 0 ) {
    """
    shiver_map_reads.sh \
        ${initdir} \
        ${params.config} \
        ${contigs} \
        ${id} \
        ${blast} \
        ${shiverRef} \
        ${read1} \
        ${read2}
    rm temp_* 
    rm *PreDedup.bam
    
    """ 
    } else {
     """
    touch ${id}.blast
    touch ${id}_contigs.fasta

    shiver_map_reads.sh \
        ${initdir} \
        ${params.config} \
        ${id}_contigs.fasta \
        ${id} \
        ${id}.blast\
        ${kallistoRef} \
        ${read1} \
        ${read2}
    rm temp_* 
    rm *PreDedup.bam
     """
  }
}


process CREATE_POL_BED {
  conda "${projectDir}/Environments/shiver.yml"
  publishDir "${params.outdir}/08_bed", mode: "copy", overwrite: true
  //debug true

  input:
    tuple val(id), path(ref), path(bam), path(bai), path(basefreqs)
    
  output:
    tuple val("${id}"), path("${id}_pol.bed")
    
  script:
  
    """
    samtools view -H ${id}*remap.bam |\
    grep -P '^@SQ' |\
    cut -f 2 |\
    sed 's/SN://g' |\
    sed '/.*/ s/\$/\t2253\t5096/g' > ${id}_pol.bed
    
    """ 
}

process FILTER_POL_BAM {
  conda "${projectDir}/Environments/shiver.yml"
  publishDir "${params.outdir}/09_pol_bam", mode: "copy", overwrite: true
  //debug true

  input:
    tuple val(id), path(pol_bed), path(ref), path(bam), path(bai), path(basefreqs)
    
  output:
    tuple val("${id}"), path("${id}_pol.bam")
    
  script:
  if ( bam[1] ) {
    """
    samtools view -b -h -L ${pol_bed} ${bam[1]} |\
    samtools sort -n -o ${id}_pol.bam -

  
    """ 
  } else {
    """
    samtools view -b -h -L ${pol_bed} ${bam[1]} |\
    samtools sort -n -o ${id}_pol.bam -

    """
  }
}


process POL_FASTQ {
  conda "${projectDir}/Environments/bedtools.yml"
  publishDir "${params.outdir}/10_pol_fastq", mode: "copy", overwrite: true
  //debug true

  input:
    tuple val(id), path(pol_bam)
    
  output:
    tuple val("${id}"), path("${id}_filtered_R*.fastq")
    
  script:
    """
    
    bamToFastq -i ${pol_bam} -fq ${id}_filtered_R1.fastq -fq2 ${id}_filtered_R2.fastq
    """ 
}


process MODIFY_HEADER {
  conda "${projectDir}/Environments/shiver.yml"
  publishDir "${params.outdir}/11_header_fastq", mode: "copy", overwrite: true
  debug true

  input:
     tuple val(id), path(reads)
    
  output:
    tuple val("${id}"), path("${id}_R*.fastq.gz")
     
  script:
    """
    cat ${reads[0]} |\
      awk -F/1 '{if (NR%4 == 1) {print \$1 " 1"} else print}' |\
      gzip -c > ${id}_R1.fastq.gz
    rm ${reads[0]}

    cat ${reads[1]} |\
      awk -F/2 '{if (NR%4 == 1) {print \$1 " 2"} else print}' |\
      gzip -c > ${id}_R2.fastq.gz
    rm ${reads[1]}
    
    """ 
}
// **************************************INPUT CHANNELS***************************************************
ch_fastq_pairs = Channel.fromFilePairs("${projectDir}/RawData/*_R{1,2}*.fastq.gz", checkIfExists: true)

workflow {

  // ****************************************KRAKEN2******************************************************
  ch_kraken2_report = KRAKEN2_CLASSIFY(ch_fastq_pairs, params.krakendb)
  // *************************************SHIVER PART*****************************************************
  ch_initdir = INITIALISATION()
  ch_kallisto_index = KALLISTO_INDEX(ch_initdir.ExistingRefsUngapped)
  ch_kallisto_index_reads = ch_kallisto_index.combine(ch_fastq_pairs)
  ch_kallisto_quant = KALLISTO_QUANT(ch_kallisto_index_reads)
  ch_bestRef = BEST_ALIGNMENT(ch_initdir.IndividualRefs, ch_kallisto_quant)
  ch_fastq_id_header = FASTQ_ID_HEADER(ch_fastq_pairs)
  ch_iva_contigs = IVA_CONTIGS(ch_fastq_pairs)
  ch_wRef = ALIGN_CONTIGS(ch_initdir.InitDir, ch_iva_contigs)
  // Combine according to a key that is the first value of every first element, which is a list
  ch_map_args = ch_bestRef.combine(ch_fastq_id_header, by:0).combine(ch_iva_contigs, by:0).combine(ch_wRef, by:0)
  ch_map_out = MAP(ch_initdir.InitDir, ch_map_args)
  ch_bed = CREATE_POL_BED (ch_map_out)
  ch_bed_bam = ch_bed.combine(ch_map_out, by:0)
  ch_pol_bam = FILTER_POL_BAM (ch_bed_bam)
  ch_pol_fastq = POL_FASTQ (ch_pol_bam)
  ch_header_fastq = MODIFY_HEADER (ch_pol_fastq)
    
}
