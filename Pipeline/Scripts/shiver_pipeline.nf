nextflow.enable.dsl = 2

projectDir = "/home/beast2/rki_shiver/Pipeline"
params.trimmomatic = "${projectDir}/Scripts/bin/trimmomatic-0.36.jar"
params.gal_primers = "${projectDir}/DataShiverInit/primers_GallEtAl2012.fasta"
params.illumina_adapters = "${projectDir}/DataShiverInit/adapters_Illumina.fasta"
params.alignment = "${projectDir}/DataShiverInit/HIV1_COM_2012_genome_DNA_NoGaplessCols.fasta"
params.config = "${projectDir}/Scripts/bin/config.sh"


params.outdir = null
if (!params.outdir) {
  println "outdir: $params.outdir"
  error "Missing output directory!"
}

process RENAME_FASTQ {
  conda "/home/beast2/anaconda3/envs/python3"
  publishDir "${params.outdir}/1_renamed_fastq", mode: "copy", overwrite: true

  input:
   path file

  output:
    path "*.fastq.gz"

  script:
   """
   regex-rename '\\d{6}_\\d{2}-\\d{5}_HIV(\\d{2}-\\d{5})_\\w{2,}_?\\d{2,}?_\\w{3}_\\w{4}_(R\\d)_\\d{3}.(\\w{5}.\\w{2})' '\\1_\\2.\\3' --rename
   """
}

process INITIALISATION {
  conda "/home/beast2/anaconda3/envs/shiver"
  publishDir "${projectDir}/${params.outdir}/2_init_dir", mode: "copy", overwrite: true

  input:
     
  output:
     path "InitDir"
  script:
  
  """
  shiver_init.sh InitDir ${params.config} ${params.alignment} ${params.illumina_adapters} ${params.gal_primers}
  """

}


process IVA_CONTIGS {
  //errorStrategy 'ignore'
  conda "/home/beast2/anaconda3/envs/iva"
  publishDir "${params.outdir}/3_iva_contigs", mode: "copy", overwrite: true

  input:
    tuple val(id), path(reads)

  output:
    path "${id}"

  script:
    """
    iva -f ${reads[0]} -r ${reads[1]} --pcr_primers ${params.gal_primers} --adapters ${params.illumina_adapters} --trimmomatic ${params.trimmomatic} ${id}
    mv ${id}/contigs.fasta ${id}/${id}_contigs.fasta
    """
}

workflow {
  fastq = channel.fromPath("${projectDir}/RawData/*.fastq.gz").collect()
  renamed_fastq = RENAME_FASTQ(fastq.flatten())
  id_fastq = channel.fromFilePairs("${projectDir}/${params.outdir}/1_renamed_fastq/*_R{1,2}.fastq.gz")
  initdir = INITIALISATION()
  iva_contigs = IVA_CONTIGS(id_fastq)

}

