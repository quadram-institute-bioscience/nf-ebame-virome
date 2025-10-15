#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

/*
========================================================================================
    nfvir - A simple viromics pipeline to mine viral genomes in a metagenome
========================================================================================
*/

/*
========================================================================================
    VALIDATE INPUTS
========================================================================================
*/

// Validate required parameters
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

// Validate assembly file exists
assembly_file = file(params.assembly)
if (!assembly_file.exists()) {
    error "Assembly file does not exist: ${params.assembly}"
}

// Validate reads CSV exists
reads_csv = file(params.reads)
if (!reads_csv.exists()) {
    error "Reads CSV file does not exist: ${params.reads}"
}

// Validate geNomad database
genomad_db_dir = file(params.genomad_db)
if (!genomad_db_dir.exists() || !genomad_db_dir.isDirectory()) {
    error "geNomad database directory does not exist: ${params.genomad_db}"
}
genomad_db_index = file("${params.genomad_db}/genomad_mini_db.index")
if (!genomad_db_index.exists()) {
    error "geNomad database index file not found: ${params.genomad_db}/genomad_mini_db.index"
}

// Validate CheckV database
checkv_db_dir = file(params.checkv_db)
if (!checkv_db_dir.exists() || !checkv_db_dir.isDirectory()) {
    error "CheckV database directory does not exist: ${params.checkv_db}"
}
// Note: CheckV database validation for specific files can be added here if needed

log.info """\
    ===================================
    N F V I R   P I P E L I N E
    ===================================
    assembly      : ${params.assembly}
    reads         : ${params.reads}
    genomad_db    : ${params.genomad_db}
    checkv_db     : ${params.checkv_db}
    outdir        : ${params.outdir}
    """
    .stripIndent()

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

/*
========================================================================================
    MAIN WORKFLOW
========================================================================================
*/

workflow {

    // 1. Prepare assembly input channel
    assembly_ch = Channel.of([
        [id: assembly_file.baseName],
        assembly_file
    ])

    // 2. Run geNomad end-to-end
    GENOMAD_ENDTOEND(
        assembly_ch,
        genomad_db_dir
    )

    // 3. Run CheckV on geNomad virus output
    // Need to extract the virus fasta and decompress it
    checkv_input_ch = GENOMAD_ENDTOEND.out.virus_fasta
        .map { meta, fasta ->
            [meta, fasta]
        }

    CHECKV_ENDTOEND(
        checkv_input_ch,
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
    reads_ch = Channel
        .fromPath(params.reads)
        .splitCsv(header: true)
        .map { row ->
            def meta = [id: row.sampleID]
            def reads = [file(row.reads_R1), file(row.reads_R2)]
            return [meta, reads]
        }

    // 7. Map reads to dereplicated vOTUs
    // Combine each sample with the reference
    mapping_input_ch = reads_ch
        .combine(EXTRACT_REPSEQ.out.representatives)

    MINIMAP2_ALIGN(
        mapping_input_ch,
        true,  // bam_format
        'bai', // bam_index_extension
        false, // cigar_paf_format
        false  // cigar_bam
    )
}

/*
========================================================================================
    COMPLETION
========================================================================================
*/

workflow.onComplete {
    log.info """\
        ===================================
        Pipeline completed!
        Status    : ${workflow.success ? 'SUCCESS' : 'FAILED'}
        Duration  : ${workflow.duration}
        Output    : ${params.outdir}
        ===================================
        """
        .stripIndent()
}
