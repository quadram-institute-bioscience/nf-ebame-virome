# nfvir

![Nextflow Virome Pipeline Logo](ebame-vir.svg)

A simple viromics pipeline to mine viral genomes in a metagenome based on the [EBAME Viromics workshop](https://corebio.info/ebame-viromics/).

## Overview

This Nextflow pipeline processes metagenomic assemblies to identify, quality-check, dereplicate, and quantify viral genomes. It implements the following workflow:

1. **Viral identification** - Uses geNomad to identify viral sequences in the assembly
2. **Quality assessment** - Runs CheckV to evaluate viral sequence quality
3. **Dereplication** - Clusters viral sequences at 95% ANI with 85% alignment fraction
4. **Read mapping** - Maps reads to dereplicated vOTUs using minimap2
5. **Coverage** - Computes per-vOTU coverage/abundance across all samples with CoverM

## Requirements

- Nextflow >= 25.10.0
- Docker, Singularity, or Conda
- geNomad database
- CheckV database

## Installation

```bash
# Clone the repository
git clone https://github.com/nfvir/nfvir.git
cd nfvir

```

### Databases

The databases can be downloaded with the bundled helper pipeline
(they are written to `--outdir`, as `genomad_db/` and `checkv-db-v*/`):

```bash
nextflow run download.nf --outdir db -profile docker
```

or manually with `genomad download-database .` and `checkv download_database .`.

The download also writes `genomad-versions.yml` and `checkv-versions.yml` to
`--outdir` so the downloaded tool versions are recorded alongside the databases.
By default the databases are moved into `--outdir` as real files (not symlinks)
to avoid duplicating several GB in `work/`. Use `--download_publish_mode copy`
if you need to keep the task outputs in `work/` for `-resume`.
The download processes retry up to two times and request at least 2 CPUs / 8 GB,
scaling resources with each retry.

## Input

The pipeline requires:

1. **Assembly file** - A co-assembly in FASTA format (can be gzipped)
2. **Reads CSV** - A CSV file with the following structure:

```csv
sampleID,reads_R1,reads_R2
sample1,/path/to/sample1_R1.fastq.gz,/path/to/sample1_R2.fastq.gz
sample2,/path/to/sample2_R1.fastq.gz,/path/to/sample2_R2.fastq.gz
```

## Usage

### Basic usage

```bash
nextflow run main.nf \
  --assembly data/human_gut_assembly.fa.gz \
  --reads data/reads.csv \
  --genomad_db /path/to/genomad_db \
  --checkv_db /path/to/checkv_db \
  --outdir results \
  -profile docker
```

### Using different profiles

```bash
# With Docker
nextflow run main.nf --assembly <assembly> --reads <reads.csv> \
  --genomad_db <db> --checkv_db <db> -profile docker

# With Singularity
nextflow run main.nf --assembly <assembly> --reads <reads.csv> \
  --genomad_db <db> --checkv_db <db> -profile singularity

# With Conda
nextflow run main.nf --assembly <assembly> --reads <reads.csv> \
  --genomad_db <db> --checkv_db <db> -profile conda
```

### Run with test data

The `test` profile expects a small dataset in `data/` (`human_gut_assembly.fa.gz`
and `reads.csv`). This data is **not** shipped in the repository (`data/` is git-ignored),
so place it there first:

```bash
nextflow run main.nf \
  --genomad_db /path/to/genomad_db \
  --checkv_db /path/to/checkv_db \
  -profile test,docker
```

## Parameters

### Required parameters

| Parameter | Description |
|-----------|-------------|
| `--assembly` | Path to the co-assembly FASTA file |
| `--reads` | Path to the CSV file containing sample reads |
| `--genomad_db` | Path to the geNomad database directory |
| `--checkv_db` | Path to the CheckV database directory |

### Optional parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--outdir` | `./results` | Output directory |
| `--max_cpus` | `8` | Maximum CPUs per job |
| `--max_memory` | `32.GB` | Maximum memory per job |
| `--max_time` | `240.h` | Maximum time per job |

## Output

The pipeline produces the following output directories:

```
results/
├── genomad/              # geNomad outputs (viral identification)
├── checkv/               # CheckV outputs (quality assessment)
├── dereplicated-votus/   # Dereplicated viral sequences
├── alignments/           # BAM files from read mapping
├── coverage/             # CoverM coverage table (vOTUs x samples)
└── pipeline_info/        # Execution reports and logs
```

### Key output files

- `genomad/genomad-out/*_summary/*_virus.fna.gz` - Identified viral sequences
- `genomad/genomad-out/*_summary/*_virus_summary.tsv` - Summary of viral sequences
- `checkv/checkv-out/quality_summary.tsv` - Quality metrics for viral sequences
- `dereplicated-votus/vOTUs.fa` - Dereplicated viral OTUs (renamed `c_000000000001`, ...)
- `dereplicated-votus/vOTU_names.tsv` - Original contig name -> vOTU name
- `dereplicated-votus/vOTU_clusters.tsv` - Clustering information (representative, members)
- `alignments/*.bam` - Sorted, indexed BAM files for each sample
- `coverage/coverage_table.tsv` - Mean coverage, covered fraction, RPKM and TPM per vOTU and sample

## Pipeline structure

```
nfvir/
├── main.nf                  # Main workflow
├── nextflow.config          # Configuration file
├── nextflow_schema.json     # Parameter schema
├── modules/                 # Process modules
│   ├── genomad.nf          # Viral identification
│   ├── checkv.nf           # Quality assessment
│   ├── dereplicate.nf      # Viral dereplication
│   ├── repseq.nf           # Representative sequence extraction
│   ├── minimap.nf          # Read mapping
│   └── coverm.nf           # Coverage calculation
├── download.nf              # Database download pipeline
├── bin/                     # Helper scripts (exposed to all processes)
└── data/                    # Test data
```

## Troubleshooting

### Database validation errors

The pipeline validates that:
- geNomad database contains `genomad_mini_db.index`
- CheckV database directory exists and contains `genome_db/`

Ensure these files are present in your database directories.

### Memory issues

If you encounter memory errors, adjust the resource limits:

```bash
nextflow run main.nf ... --max_memory 64.GB
```

### Resume failed runs

Nextflow supports resuming from the last successful step:

```bash
nextflow run main.nf ... -resume
```

## Citation

If you use this pipeline, please cite:

- **geNomad**: Camargo et al. (2023) Nature Biotechnology
- **CheckV**: Nayfach et al. (2021) Nature Biotechnology
- **minimap2**: Li (2018) Bioinformatics
- **Nextflow**: Di Tommaso et al. (2017) Nature Biotechnology

## License

MIT License

## Contact

For issues and feature requests, please use the GitHub issue tracker.
