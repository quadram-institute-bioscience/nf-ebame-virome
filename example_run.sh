#!/bin/bash

# Example command to run the nfvir pipeline
# Update the paths to your database locations before running

# Set database paths (UPDATE THESE!)
CHECKV_DB=/Users/telatina/git/virome/virome-data/db/checkv-db-v1.5
GENOMAD_DB=/Users/telatina/git/virome/virome-data/db/genomad_db
# Run with test data
nextflow run main.nf -resume \
  --assembly data/human_gut_assembly.fa.gz \
  --reads data/reads.csv \
  --genomad_db ${GENOMAD_DB} \
  --checkv_db ${CHECKV_DB} \
  --outdir results \
  --max_cpus 8 \
  --max_memory 32.GB \
  -profile docker

# Alternative: Run with your own data
# nextflow run main.nf \
#   --assembly /path/to/your/assembly.fa.gz \
#   --reads /path/to/your/reads.csv \
#   --genomad_db ${GENOMAD_DB} \
#   --checkv_db ${CHECKV_DB} \
#   --outdir results \
#   -profile docker
