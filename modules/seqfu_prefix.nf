process SEQFU_PREFIX {
    tag "$meta.id"
    label 'process_low'

    conda "bioconda::seqfu=1.22.3"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/seqfu:1.22.3--hfd12232_2':
        'quay.io/biocontainers/seqfu:1.22.3--hfd12232_2' }"

    input:
    tuple val(meta), path(virus_fasta), path(quality_summary)

    output:
    tuple val(meta), path("${meta.id}_virus.fna"),            emit: virus_fasta
    tuple val(meta), path("${meta.id}_quality_summary.tsv"),  emit: quality_summary
    path "versions.yml",                                       emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = meta.id
    """
    # Prefix every sequence ID in the viral FASTA with the assembly ID.
    # seqfu cat reads gzip transparently; output is plain FASTA for collectFile merging.
    seqfu cat --prefix "${prefix}_" ${virus_fasta} > ${prefix}_virus.fna

    # Prefix the contig_id column (column 1) in the CheckV quality summary
    # so IDs stay in sync with the renamed FASTA for downstream filtering.
    awk -F'\\t' 'BEGIN{OFS="\\t"} NR==1{print} NR>1{\$1="${prefix}_"\$1; print}' \\
        ${quality_summary} > ${prefix}_quality_summary.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        seqfu: \$(seqfu version 2>&1 | sed 's/seqfu //')
    END_VERSIONS
    """

    stub:
    def prefix = meta.id
    """
    touch ${prefix}_virus.fna
    touch ${prefix}_quality_summary.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        seqfu: 1.22.3
    END_VERSIONS
    """
}
