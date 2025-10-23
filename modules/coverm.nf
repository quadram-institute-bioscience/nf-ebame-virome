process COVERM_CONTIG {
    tag "coverage_table"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/coverm:0.7.0--hcb7b614_4' :
        'biocontainers/coverm:0.7.0--hcb7b614_4' }"

    input:
    path(bam_files)
    path(bai_files)

    output:
    path("coverage_table.tsv"), emit: coverage
    path "versions.yml"       , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def methods = task.ext.methods ?: 'mean covered_fraction rpkm tpm'
    """
    coverm contig \\
        --bam-files ${bam_files} \\
        --methods ${methods} \\
        --output-file coverage_table.tsv \\
        --exclude-supplementary \\
        --threads ${task.cpus} \\
        ${args}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        coverm: \$(coverm --version 2>&1 | sed 's/coverm //g')
    END_VERSIONS
    """

    stub:
    """
    touch coverage_table.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        coverm: \$(coverm --version 2>&1 | sed 's/coverm //g')
    END_VERSIONS
    """
}
