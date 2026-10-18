# nfvir

![Nextflow Virome Pipeline Logo](ebame-vir.svg)

A simple viromics pipeline to mine viral genomes in a metagenome based on the [EBAME Viromics workshop](https://corebio.info/ebame-viromics/).

## Overview

This Nextflow pipeline processes metagenomic assemblies to identify, quality-check, dereplicate, and quantify viral genomes. It implements the following workflow:

1. **Viral identification** - Uses geNomad to identify viral sequences in the assembly
2. **Quality assessment** - Runs CheckV to evaluate viral sequence quality
3. **Dereplication** - Clusters viral sequences at 95% ANI with 85% target coverage using `votuderep`
4. **Read mapping** - Maps reads to dereplicated vOTUs using BWA (default) or minimap2 (`--minimap`)
5. **Coverage** - Computes per-vOTU coverage/abundance across all samples with BamCountRefs (`bamtocov`)

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

### Choosing the mapper

BWA is used by default (with a BWA index built once for the dereplicated
vOTUs). To use minimap2 instead, add `--minimap`:

```bash
nextflow run main.nf ... --minimap
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
| `--genomad_cleanup` | `true` | Delete geNomad intermediate files (`--cleanup`) |
| `--checkv_min_quality` | `all` | Minimum CheckV tier kept for dereplication (`all`, `low`, `medium`, `high`, `complete`) |
| `--minimap` | `false` | Use minimap2 instead of BWA for read mapping |

## Output

The pipeline produces the following output directories:

```
results/
├── genomad/              # Final geNomad summary files (no intermediate DB files)
├── checkv/               # CheckV quality tables and sequences (no tmp/)
├── dereplicated-votus/   # Dereplicated viral sequences and quality table
├── alignments/           # BAM files from read mapping
├── coverage/             # BamCountRefs coverage tables (vOTUs x samples)
└── pipeline_info/        # Execution reports and logs
```

Only the final files are published. The `genomad-out/` and `checkv-out/`
directory wrappers, MMseqs2 databases, and `checkv-out/tmp/` are deliberately
not published.

### Key output files

- `genomad/*_summary/*_virus.fna.gz` - Identified viral sequences
- `genomad/*_summary/*_virus_summary.tsv` - Summary of viral sequences
- `checkv/quality_summary.tsv` - Quality metrics for viral sequences
- `dereplicated-votus/dereplicated_vOTUs.fasta` - Raw `votuderep` output (representatives, original names)
- `dereplicated-votus/vOTU_representatives.txt` - Representative sequence IDs retained by `votuderep`
- `dereplicated-votus/vOTUs.fa` - Dereplicated viral OTUs (renamed `c_000000000001`, ...)
- `dereplicated-votus/vOTU_names.tsv` - Original contig name -> vOTU name
- `dereplicated-votus/vOTU_quality.tsv` - vOTU name with CheckV quality, completeness and contamination
- `alignments/*.bam` - Sorted BAM files for each sample (`.bam.csi` with BWA, `.bam.bai` with `--minimap`)
- `coverage/coverage_counts.tsv` - Read counts per vOTU and sample
- `coverage/coverage_length.tsv` - Reference sequence lengths
- `coverage/coverage_mean.tsv` - Mean coverage depth
- `coverage/coverage_covered_fraction.tsv` - Fraction of each reference covered by reads
- `coverage/coverage_rpkm.tsv` - RPKM values
- `coverage/coverage_tpm.tsv` - TPM values

All BamCountRefs tables share the same layout: `Contig` followed by one
column per sample.

### CheckV quality filtering

By default (`--checkv_min_quality all`) every geNomad virus is dereplicated,
including CheckV `Low-quality` and `Not-determined` contigs. This preserves
viral signal from short or novel fragments, and the per-vOTU
`vOTU_quality.tsv` table lets you filter downstream.

Set `--checkv_min_quality medium` (or `high`/`complete`) to remove contigs
below that CheckV tier *before* clustering. `Not-determined` contigs are
excluded by any value other than `all`.

## Pipeline structure

```
nfvir/
├── main.nf                  # Main workflow
├── nextflow.config          # Configuration file
├── nextflow_schema.json     # Parameter schema
├── modules/                 # Process modules
│   ├── genomad.nf          # Viral identification
│   ├── checkv.nf           # Quality assessment
│   ├── votuderep.nf        # Viral dereplication
│   ├── repseq.nf           # Representative sequence extraction
│   ├── bwa.nf              # BWA index and read mapping (default)
│   ├── minimap.nf          # minimap2 read mapping (--minimap)
│   └── bamcountrefs.nf     # Coverage calculation
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
- **votuderep**: https://github.com/quadram-institute-bioscience/votuderep
- **BWA**: Li & Durbin (2009) Bioinformatics
- **minimap2**: Li (2018) Bioinformatics
- **BamCountRefs / bamtocov**: https://github.com/telatin/bamtocov
- **Nextflow**: Di Tommaso et al. (2017) Nature Biotechnology

## License

MIT License

## Contact

For issues and feature requests, please use the GitHub issue tracker.
