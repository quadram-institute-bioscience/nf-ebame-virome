process BAMCOUNTREFS {
    tag "coverage"
    label 'process_medium'

    conda "bioconda::bamtocov=2.11.0"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bamtocov%3A2.11.0--hf50e46a_0' :
        'quay.io/biocontainers/bamtocov:2.11.0--hf50e46a_0' }"

    input:
    path(bam_files)
    path(index_files)  // staged next to the BAMs; bamcountrefs loads them automatically

    output:
    path("coverage_*.tsv"), emit: coverage
    path "versions.yml"   , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: '--mean --covered-ratio --rpkm --tpm --length'
    """
    bamcountrefs \\
        -T $task.cpus \\
        -o coverage \\
        $args \\
        ${bam_files}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bamcountrefs: \$(bamcountrefs --version 2>&1 | sed 's/^.* //')
    END_VERSIONS
    """

    stub:
    """
    touch coverage_counts.tsv
    touch coverage_covered_fraction.tsv
    touch coverage_length.tsv
    touch coverage_mean.tsv
    touch coverage_rpkm.tsv
    touch coverage_tpm.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        bamcountrefs: 2.11.0
    END_VERSIONS
    """
}
