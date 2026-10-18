#!/usr/bin/env nextflow

/*
========================================================================================
    A pipeline to download databases for nfvir
========================================================================================
*/

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

    main:
    if (!(params.download_publish_mode in ['move', 'copy', 'hardlink'])) {
        error "download_publish_mode must be one of: move, copy, hardlink (symlinks are not supported)"
    }

    log.info """\
        ===================================
        N F V I R - D O W N L O A D
        ===================================
        outdir        : ${params.outdir}
        """.stripIndent()

    DOWNLOAD_GENOMAD()
    DOWNLOAD_CHECKV()

    onComplete:
    log.info """\
        ===================================
        Download completed!
        Status    : ${workflow.success ? 'SUCCESS' : 'FAILED'}
        Duration  : ${workflow.duration}
        Output    : ${params.outdir}
        ===================================
        """.stripIndent()
}
