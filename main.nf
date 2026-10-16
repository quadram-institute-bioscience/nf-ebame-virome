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
include { DEREPLICATE      } from './modules/dereplicate'
include { EXTRACT_REPSEQ   } from './modules/repseq'
include { MINIMAP2_ALIGN   } from './modules/minimap'
include { COVERM_CONTIG    } from './modules/coverm'

/*
========================================================================================
    MAIN WORKFLOW
========================================================================================
*/

workflow {

    main:

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

    // 4. Dereplicate the viral sequences
    dereplicate_input_ch = GENOMAD_ENDTOEND.out.virus_fasta
        .join(CHECKV_ENDTOEND.out.quality_summary)

    DEREPLICATE(
        dereplicate_input_ch
    )

    // 5. Extract representative sequences
    repseq_input_ch = GENOMAD_ENDTOEND.out.virus_fasta
        .join(DEREPLICATE.out.representative_ids)

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
    mapping_input_ch = reads_ch
        .combine(EXTRACT_REPSEQ.out.representatives)

    MINIMAP2_ALIGN(
        mapping_input_ch,
        true,  // bam_format
        'bai', // bam_index_extension
        false, // cigar_paf_format
        false  // cigar_bam
    )

    // 8. Calculate coverage metrics across all samples
    bam_files_ch = MINIMAP2_ALIGN.out.bam.map { meta, bam -> bam }.collect()
    bai_files_ch = MINIMAP2_ALIGN.out.index.map { meta, bai -> bai }.collect()

    COVERM_CONTIG(
        bam_files_ch,
        bai_files_ch
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
