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

include { MEGAHIT                              } from './modules/megahit'
include { GENOMAD_ENDTOEND                     } from './modules/genomad'
include { CHECKV_ENDTOEND                      } from './modules/checkv'
include { CHECKV_ENDTOEND as CHECKV_VOTUS      } from './modules/checkv'
include { SEQFU_PREFIX                         } from './modules/seqfu_prefix'
include { VOTUDEREP                            } from './modules/votuderep'
include { EXTRACT_REPSEQ                       } from './modules/repseq'
include { BWA_INDEX                            } from './modules/bwa'
include { BWA_MEM                              } from './modules/bwa'
include { MINIMAP2_ALIGN                       } from './modules/minimap'
include { BAMCOUNTREFS                         } from './modules/bamcountrefs'

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
              nextflow run main.nf --reads <reads.csv> \\
                                   --genomad_db <genomad_db> \\
                                   --checkv_db <checkv_db> \\
                                   [ --assembly <assembly.fa[.gz]> |
                                     --assemblies <assemblies.csv> ] \\
                                   [options] \\
                                   -profile <docker|singularity|podman|conda|standard>

            Assembly input (choose one, or omit to assemble with MEGAHIT):
              --assembly   PATH    Single co-assembly FASTA file (optionally gzipped)
              --assemblies PATH    CSV file with columns: assemblyID, fasta

            Required arguments:
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

            Example (single assembly):
              nextflow run main.nf \\
                --assembly assembly.fa.gz \\
                --reads reads.csv \\
                --genomad_db /path/to/genomad_db \\
                --checkv_db /path/to/checkv_db \\
                --outdir results \\
                -profile docker

            Example (multiple assemblies):
              nextflow run main.nf \\
                --assemblies assemblies.csv \\
                --reads reads.csv \\
                --genomad_db /path/to/genomad_db \\
                --checkv_db /path/to/checkv_db \\
                -profile docker

            Example (no assembly — MEGAHIT each sample):
              nextflow run main.nf \\
                --reads reads.csv \\
                --genomad_db /path/to/genomad_db \\
                --checkv_db /path/to/checkv_db \\
                -profile docker
            """.stripIndent()
        exit 0
    }

    // 0. Validate inputs

    // Assembly modes are mutually exclusive
    if (params.assembly && params.assemblies) {
        error "Specify --assembly OR --assemblies, not both"
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

    def use_minimap = params.minimap?.toString() == 'true'

    // Validate DB paths (skip in stub-run)
    def genomad_db_dir = file(params.genomad_db)
    def checkv_db_dir  = file(params.checkv_db)
    if (!workflow.stubRun) {
        if (!genomad_db_dir.isDirectory()) {
            error "geNomad database directory does not exist: ${params.genomad_db}"
        }
        if (!file("${params.genomad_db}/genomad_mini_db.index").exists()) {
            error "geNomad database index file not found: ${params.genomad_db}/genomad_mini_db.index"
        }
        if (!checkv_db_dir.isDirectory()) {
            error "CheckV database directory does not exist: ${params.checkv_db}"
        }
        if (!file("${params.checkv_db}/genome_db").isDirectory()) {
            error "CheckV database looks incomplete (genome_db/ not found): ${params.checkv_db}"
        }
    }

    // 1. Parse reads CSV — always needed (MEGAHIT and/or read mapping)
    def reads_csv = file(params.reads)
    if (!workflow.stubRun && !reads_csv.exists()) {
        error "Reads CSV file does not exist: ${params.reads}"
    }

    reads_ch = channel
        .fromPath(params.reads)
        .splitCsv(header: true)
        .map { row ->
            if (!row.sampleID || !row.reads_R1 || !row.reads_R2) {
                error "Reads CSV must have non-empty columns sampleID, reads_R1, reads_R2 (problem row: ${row})"
            }
            def meta  = [id: row.sampleID]
            def reads = [file(row.reads_R1, checkIfExists: true), file(row.reads_R2, checkIfExists: true)]
            return [meta, reads]
        }

    // 2. Build assembly channel — three modes
    if (params.assembly) {
        // --- Mode A: single provided assembly ---
        def assembly_file = file(params.assembly)
        if (!workflow.stubRun && !assembly_file.exists()) {
            error "Assembly file does not exist: ${params.assembly}"
        }
        assembly_ch = channel.of([[id: assembly_file.simpleName], assembly_file])

    } else if (params.assemblies) {
        // --- Mode B: multiple provided assemblies (CSV: assemblyID,fasta) ---
        def assemblies_csv = file(params.assemblies)
        if (!workflow.stubRun && !assemblies_csv.exists()) {
            error "Assemblies CSV file does not exist: ${params.assemblies}"
        }
        assembly_ch = channel
            .fromPath(params.assemblies)
            .splitCsv(header: true)
            .map { row ->
                if (!row.assemblyID || !row.fasta) {
                    error "Assemblies CSV must have non-empty columns assemblyID, fasta (problem row: ${row})"
                }
                [[id: row.assemblyID], file(row.fasta, checkIfExists: !workflow.stubRun)]
            }

    } else {
        // --- Mode C: no assembly provided — run MEGAHIT on each sample ---
        MEGAHIT(reads_ch.map { meta, reads -> [meta, reads[0], reads[1]] })
        assembly_ch = MEGAHIT.out.contigs
    }

    log.info """\
        ===================================
        N F V I R   P I P E L I N E
        ===================================
        assembly mode : ${ params.assembly   ? "single: ${params.assembly}" :
                           params.assemblies ? "multi:  ${params.assemblies}" :
                                              'per-sample (MEGAHIT)' }
        reads         : ${params.reads}
        genomad_db    : ${params.genomad_db}
        checkv_db     : ${params.checkv_db}
        checkv_quality: ${params.checkv_min_quality}
        mapper        : ${use_minimap ? 'minimap2' : 'bwa'}
        outdir        : ${params.outdir}
        """.stripIndent()

    // 3. Run geNomad on every assembly
    GENOMAD_ENDTOEND(assembly_ch, genomad_db_dir)

    // 4. Run CheckV on each assembly's viral sequences
    CHECKV_ENDTOEND(GENOMAD_ENDTOEND.out.virus_fasta, checkv_db_dir)

    // 5. Prefix sequence IDs with the assembly ID so IDs are unique after merging.
    //    Both the FASTA headers and the contig_id column of the quality summary
    //    receive the same "{assemblyID}_" prefix to keep them in sync.
    SEQFU_PREFIX(
        GENOMAD_ENDTOEND.out.virus_fasta
            .join(CHECKV_ENDTOEND.out.quality_summary)
    )

    // 6. Concatenate prefixed FASTAs and quality summaries across all assemblies
    merged_fasta_ch = SEQFU_PREFIX.out.virus_fasta
        .map  { meta, fasta -> fasta }
        .collectFile(name: 'all_viruses.fna', sort: 'deep')
        .map  { fasta -> [[id: 'merged'], fasta] }

    merged_quality_ch = SEQFU_PREFIX.out.quality_summary
        .map  { meta, tsv -> tsv }
        .collectFile(name: 'all_quality_summary.tsv', keepHeader: true, skip: 1, sort: 'deep')
        .map  { tsv -> [[id: 'merged'], tsv] }

    // multiMap lets both VOTUDEREP and EXTRACT_REPSEQ consume the merged channels
    merged_fasta_ch
        .join(merged_quality_ch)
        .multiMap { meta, fasta, tsv ->
            for_votuderep: [meta, fasta, tsv]
            for_repseq:    [meta, fasta, tsv]
        }
        .set { merged }

    // 7. Dereplicate across all assemblies into a single vOTU set
    VOTUDEREP(merged.for_votuderep)

    // 8. Extract and rename representative sequences
    EXTRACT_REPSEQ(
        merged.for_repseq
            .join(VOTUDEREP.out.representative_ids)
            .map { meta, fasta, tsv, rep_ids -> [meta, fasta, rep_ids, tsv] }
    )

    // 9. Re-assess the final dereplicated vOTUs with CheckV.
    //    votus_ch is a value channel (single item) reused by CHECKV_VOTUS and read-mapping.
    votus_ch = EXTRACT_REPSEQ.out.representatives

    CHECKV_VOTUS(votus_ch, checkv_db_dir)

    // 10. Map reads against the dereplicated vOTUs
    if (use_minimap) {
        MINIMAP2_ALIGN(
            reads_ch.combine(votus_ch),
            true,  // bam_format
            'bai', // bam_index_extension
            false, // cigar_paf_format
            false  // cigar_bam
        )
        bam_files_ch   = MINIMAP2_ALIGN.out.bam.map   { meta, bam   -> bam   }.collect()
        index_files_ch = MINIMAP2_ALIGN.out.index.map { meta, index -> index }.collect()
    } else {
        BWA_INDEX(votus_ch)
        BWA_MEM(
            reads_ch,
            BWA_INDEX.out.index,
            votus_ch,
            true // sort_bam
        )
        bam_files_ch   = BWA_MEM.out.bam.map { meta, bam   -> bam   }.collect()
        index_files_ch = BWA_MEM.out.csi.map { meta, index -> index }.collect()
    }

    // 11. Calculate coverage metrics across all samples
    BAMCOUNTREFS(bam_files_ch, index_files_ch)

    workflow.onComplete {
        log.info """\
            ===================================
            Pipeline completed!
            Status    : ${workflow.success ? 'SUCCESS' : 'FAILED'}
            Duration  : ${workflow.duration}
            Output    : ${params.outdir}
            ===================================
            """.stripIndent()
    }

}
