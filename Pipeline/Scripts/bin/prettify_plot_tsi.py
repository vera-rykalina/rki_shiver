#!/usr/bin/env python3

# Import libraries
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
import sys
import re

infilename = sys.argv[1]


# Read .csv file
f = open(infilename, "r")
df = pd.read_csv(f, sep = ",", index_col=False)
f.close()

# Create some variables
name1 = infilename.rsplit("/")[-1] # gives a file name.csv

# Keep only useful columns (host.id and all other which start with RF_)
df = df.filter(regex = "^host|^RF_", axis = 1)

# Create "Scount" columns bases on "host.id" (extract our internal ID)
df["Scount"] = df["host.id"].str.extract("\d{6}_\d{2}-\d{5}_HIV(\d{2}-\d{5})_\w{2}\d{1,}_\w{2,}_\w{4,}", expand = True)

# Swap columns to have "Scount" first
df = df.iloc[:, [-1, 0] + list(range(1, df.shape[1] - 1 ))]

# Sort df by "Scount"
df.sort_values(by=["Scount"], inplace = True)

# Convert years to months
df["RF_pred_linear"] = df["RF_pred_linear"].apply(lambda x: x*12)

# Round "RF_pred_linear" values
df["RF_pred_linear"] = df["RF_pred_linear"].apply(lambda x: round(x, 3))

# Create a clean csv file
df.to_csv("phylo_tsi_prettified.csv", sep=",", header = True, index = False, encoding="utf-8")

# Visualisation
sns.set_style("darkgrid")
sns.set_context("poster")
fig, ax = plt.subplots(figsize=(16, 12))

# Plot
barplot = sns.barplot(x="RF_pred_linear", y="Scount",
                          data=df, palette="GnBu_d")

# Set limits and tichs for x
barplot.set_xlim(0, int(df["RF_pred_linear"].max() + 7))
barplot.set_xticks(range(0, int(df["RF_pred_linear"].max() + 7), 6))

# Add labels and title
ax.set(xlabel = "TSI (months)", 
       title = "Estimation of Time since Infection using PhyloTSI Model\n(full-length paired-end sequencing)\n")

# Add some extra white space
fig.tight_layout(pad=1)

# Add values to bars
for container in ax.containers:
    ax.bar_label(container)

# Save plot as png figure
plt.savefig("tsi_barplot.png", dpi = 300)
#plt.show()
