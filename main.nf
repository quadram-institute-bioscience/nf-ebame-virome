#!/usr/bin/env nextflow

/*
========================================================================================
    nfvir - A simple viromics pipeline to mine viral genomes in a metagenome
========================================================================================
*/

/*
========================================================================================
    IMPORT MODULES
========================================================================================
*/

include { GENOMAD_ENDTOEND } from './modules/genomad'
include { CHECKV_ENDTOEND  } from './modules/checkv'
include { VOTUDEREP       } from './modules/votuderep'
include { EXTRACT_REPSEQ   } from './modules/repseq'
include { BWA_INDEX        } from './modules/bwa'
include { BWA_MEM          } from './modules/bwa'
include { MINIMAP2_ALIGN   } from './modules/minimap'
include { BAMCOUNTREFS     } from './modules/bamcountrefs'

/*
========================================================================================
    MAIN WORKFLOW
========================================================================================
*/

workflow {

    main:

    // Print help and exit when --help is requested
    if (params.help?.toString() == 'true') {
        log.info """\
            ======================================================
            nfvir - A simple viromics pipeline to mine viral genomes
            ======================================================

            Usage:
              nextflow run main.nf --assembly <assembly.fa[.gz]> \\
                                   --reads <reads.csv> \\
                                   --genomad_db <genomad_db> \\
                                   --checkv_db <checkv_db> \\
                                   [options] \\
                                   -profile <docker|singularity|podman|conda|standard>

            Required arguments:
              --assembly   PATH    Co-assembly FASTA file (optionally gzipped)
              --reads      PATH    CSV file with columns: sampleID, reads_R1, reads_R2
              --genomad_db PATH    geNomad database directory
              --checkv_db  PATH    CheckV database directory

            Optional arguments:
              --outdir                             PATH    Output directory (default: ./results)
              --checkv_min_quality                 STR     Minimum CheckV tier kept for
                                                           dereplication: all, low, medium,
                                                           high, complete (default: all)
              --minimap                                    Use minimap2 instead of BWA for read mapping
              --genomad_cleanup                    BOOL    Delete geNomad intermediate files
                                                           (default: true)
              --max_cpus                           INT     Maximum CPUs per job (default: 8)
              --max_memory                         STR     Maximum memory per job (default: 32.GB)
              --max_time                           STR     Maximum time per job (default: 240.h)
              --singularity_pull_docker_container  BOOL    Pull Docker containers with Singularity
                                                           (default: false)
              --help                                       Show this help message and exit

            Profiles:
              docker, singularity, podman, conda, standard, test

            Example:
              nextflow run main.nf \\
                --assembly assembly.fa.gz \\
                --reads reads.csv \\
                --genomad_db /path/to/genomad_db \\
                --checkv_db /path/to/checkv_db \\
                --outdir results \\
                -profile docker
            """.stripIndent()
        exit 0
    }

    // 0. Validate inputs
    if (!params.assembly) {
        error "Please provide an assembly file with --assembly"
    }
    if (!params.reads) {
        error "Please provide a reads CSV file with --reads"
    }
    if (!params.genomad_db) {
        error "Please provide a geNomad database path with --genomad_db"
    }
    if (!params.checkv_db) {
        error "Please provide a CheckV database path with --checkv_db"
    }
    if (!(params.checkv_min_quality in ['all', 'low', 'medium', 'high', 'complete'])) {
        error "checkv_min_quality must be one of: all, low, medium, high, complete"
    }

    // Accept both a boolean (config/YAML) and a CLI string
    def use_minimap = params.minimap?.toString() == 'true'

    def assembly_file = file(params.assembly)
    if (!assembly_file.exists()) {
        error "Assembly file does not exist: ${params.assembly}"
    }

    def reads_csv = file(params.reads)
    if (!reads_csv.exists()) {
        error "Reads CSV file does not exist: ${params.reads}"
    }

    def genomad_db_dir = file(params.genomad_db)
    if (!genomad_db_dir.isDirectory()) {
        error "geNomad database directory does not exist: ${params.genomad_db}"
    }
    if (!file("${params.genomad_db}/genomad_mini_db.index").exists()) {
        error "geNomad database index file not found: ${params.genomad_db}/genomad_mini_db.index"
    }

    def checkv_db_dir = file(params.checkv_db)
    if (!checkv_db_dir.isDirectory()) {
        error "CheckV database directory does not exist: ${params.checkv_db}"
    }
    if (!file("${params.checkv_db}/genome_db").isDirectory()) {
        error "CheckV database looks incomplete (genome_db/ not found): ${params.checkv_db}"
    }

    log.info """\
        ===================================
        N F V I R   P I P E L I N E
        ===================================
        assembly      : ${params.assembly}
        reads         : ${params.reads}
        genomad_db    : ${params.genomad_db}
        checkv_db     : ${params.checkv_db}
        checkv_quality: ${params.checkv_min_quality}
        mapper        : ${use_minimap ? 'minimap2' : 'bwa'}
        outdir        : ${params.outdir}
        """.stripIndent()

    // 1. Prepare assembly input channel
    assembly_ch = channel.of([
        [id: assembly_file.simpleName],
        assembly_file
    ])

    // 2. Run geNomad end-to-end
    GENOMAD_ENDTOEND(
        assembly_ch,
        genomad_db_dir
    )

    // 3. Run CheckV on geNomad virus output
    CHECKV_ENDTOEND(
        GENOMAD_ENDTOEND.out.virus_fasta,
        checkv_db_dir
    )

    // 4. Dereplicate the viral sequences with votuderep
    dereplicate_input_ch = GENOMAD_ENDTOEND.out.virus_fasta
        .join(CHECKV_ENDTOEND.out.quality_summary)

    VOTUDEREP(
        dereplicate_input_ch
    )

    // 5. Extract representative sequences and annotate them with CheckV quality
    repseq_input_ch = GENOMAD_ENDTOEND.out.virus_fasta
        .join(VOTUDEREP.out.representative_ids)
        .join(CHECKV_ENDTOEND.out.quality_summary)

    EXTRACT_REPSEQ(
        repseq_input_ch
    )

    // 6. Parse reads CSV and create channel
    reads_ch = channel
        .fromPath(params.reads)
        .splitCsv(header: true)
        .map { row ->
            if (!row.sampleID || !row.reads_R1 || !row.reads_R2) {
                error "Reads CSV must have non-empty columns sampleID, reads_R1, reads_R2 (problem row: ${row})"
            }
            def meta = [id: row.sampleID]
            def reads = [file(row.reads_R1, checkIfExists: true), file(row.reads_R2, checkIfExists: true)]
            return [meta, reads]
        }

    // 7. Map reads to dereplicated vOTUs
    //    BWA is the default; pass --minimap to use minimap2 instead.
    if (use_minimap) {
        mapping_input_ch = reads_ch
            .combine(EXTRACT_REPSEQ.out.representatives)

        MINIMAP2_ALIGN(
            mapping_input_ch,
            true,  // bam_format
            'bai', // bam_index_extension
            false, // cigar_paf_format
            false  // cigar_bam
        )

        bam_files_ch   = MINIMAP2_ALIGN.out.bam.map { meta, bam -> bam }.collect()
        index_files_ch = MINIMAP2_ALIGN.out.index.map { meta, index -> index }.collect()
    } else {
        // Build the BWA index once for the dereplicated vOTUs
        BWA_INDEX(EXTRACT_REPSEQ.out.representatives)

        // first() makes the single index/reference reusable for every sample
        BWA_MEM(
            reads_ch,
            BWA_INDEX.out.index.first(),
            EXTRACT_REPSEQ.out.representatives.first(),
            true // sort_bam
        )

        bam_files_ch   = BWA_MEM.out.bam.map { meta, bam -> bam }.collect()
        index_files_ch = BWA_MEM.out.csi.map { meta, index -> index }.collect()
    }

    // 8. Calculate coverage metrics across all samples
    BAMCOUNTREFS(
        bam_files_ch,
        index_files_ch
    )

    onComplete:
    log.info """\
        ===================================
        Pipeline completed!
        Status    : ${workflow.success ? 'SUCCESS' : 'FAILED'}
        Duration  : ${workflow.duration}
        Output    : ${params.outdir}
        ===================================
        """.stripIndent()
}
