#!/bin/bash

# Example command to run the nfvir pipeline.
# Point CHECKV_DB / GENOMAD_DB to your databases (or download them with:
#   nextflow run download.nf --outdir db -profile docker )

CHECKV_DB=${CHECKV_DB:-db/checkv-db-v1.5}
GENOMAD_DB=${GENOMAD_DB:-db/genomad_db}
ASSEMBLY=${ASSEMBLY:-data/mini.fa}
READS=${READS:-data/reads.csv}

nextflow run main.nf -resume \
  --assembly "${ASSEMBLY}" \
  --reads "${READS}" \
  --genomad_db "${GENOMAD_DB}" \
  --checkv_db "${CHECKV_DB}" \
  --outdir results \
  --max_cpus 8 \
  --max_memory 32.GB \
  -profile docker
