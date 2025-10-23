process DOWNLOAD_GENOMAD {
    label 'process_high'

    publishDir "${params.outdir}", mode: 'copy'

    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/genomad:1.9.0--pyhdfd78af_1':
        'biocontainers/genomad:1.9.0--pyhdfd78af_1' }"

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
}
