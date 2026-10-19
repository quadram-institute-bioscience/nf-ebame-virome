process DOWNLOAD_CHECKV {
    tag "checkv_db"
    label 'process_download'

    publishDir(
        path: "${params.outdir}",
        mode: params.download_publish_mode,
        saveAs: { filename -> filename == 'versions.yml' ? 'checkv-versions.yml' : filename }
    )

    conda "bioconda::checkv=1.0.3"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/checkv:1.0.3--pyhdfd78af_0':
        'quay.io/biocontainers/checkv:1.0.3--pyhdfd78af_0' }"

    output:
    path "checkv-db-v*"
    path "versions.yml"

    script:
    """
    checkv download_database ./

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        checkv: \$(checkv -h 2>&1  | sed -n 's/^.*CheckV v//; s/: assessing.*//; 1p')
    END_VERSIONS
    """

    stub:
    """
    mkdir -p checkv-db-v1.5
    touch checkv-db-v1.5/.stub

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        checkv: 1.0.3
    END_VERSIONS
    """
}
