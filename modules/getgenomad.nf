process DOWNLOAD_GENOMAD {
    tag "genomad_db"
    label 'process_download'

    publishDir(
        path: "${params.outdir}",
        mode: params.download_publish_mode,
        saveAs: { filename -> filename == 'versions.yml' ? 'genomad-versions.yml' : filename }
    )

    conda "bioconda::genomad=1.9.0"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/genomad:1.9.0--pyhdfd78af_1':
        'quay.io/biocontainers/genomad:1.9.0--pyhdfd78af_1' }"

    output:
    path "genomad_db"
    path "versions.yml"

    script:
    """
    genomad download-database .

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        genomad: \$(echo \$(genomad --version 2>&1) | sed 's/^.*geNomad, version //; s/ .*\$//')
    END_VERSIONS
    """

    stub:
    """
    mkdir -p genomad_db
    touch genomad_db/.stub

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        genomad: 1.9.0
    END_VERSIONS
    """
}
