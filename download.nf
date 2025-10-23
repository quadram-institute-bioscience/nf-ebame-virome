#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

/*
========================================================================================
    A pipeline to download databases for nfvir
========================================================================================
*/

if (!params.outdir) {
    error "Please provide an output directory with --outdir"
}

log.info """
    ===================================
    N F V I R - D O W N L O A D
    ===================================
    outdir        : ${params.outdir}
    """.stripIndent()

/*
========================================================================================
    IMPORT MODULES
========================================================================================
*/

include { DOWNLOAD_GENOMAD } from './modules/getgenomad'
include { DOWNLOAD_CHECKV } from './modules/getcheckv'

/*
========================================================================================
    MAIN WORKFLOW
========================================================================================
*/

workflow {
    DOWNLOAD_GENOMAD()
    DOWNLOAD_CHECKV()
}

/*
========================================================================================
    COMPLETION
========================================================================================
*/

workflow.onComplete {
    log.info """
        ===================================
        Download completed!
        Status    : ${workflow.success ? 'SUCCESS' : 'FAILED'}
        Duration  : ${workflow.duration}
        Output    : ${params.outdir}
        ===================================
        """.stripIndent()
}
