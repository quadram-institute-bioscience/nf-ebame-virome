process CHECKV_ENDTOEND {
    tag "$meta.id"
    label 'process_medium'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/checkv:1.0.3--pyhdfd78af_0':
        'biocontainers/checkv:1.0.3--pyhdfd78af_0' }"

    input:
    tuple val(meta), path(fasta)
    path db

    output:
    tuple val(meta), path("checkv-out/quality_summary.tsv") , emit: quality_summary
    tuple val(meta), path("checkv-out/completeness.tsv")    , emit: completeness
    tuple val(meta), path("checkv-out/contamination.tsv")   , emit: contamination
    tuple val(meta), path("checkv-out/complete_genomes.tsv"), emit: complete_genomes
    tuple val(meta), path("checkv-out/proviruses.fna")      , emit: proviruses
    tuple val(meta), path("checkv-out/viruses.fna")         , emit: viruses
    tuple val(meta), path("checkv-out")                     , emit: checkv_dir
    path "versions.yml"                                     , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Decompress input if needed
    if [[ ${fasta} == *.gz ]]; then
        gunzip -c ${fasta} > input_viruses.fna
        INPUT_FILE="input_viruses.fna"
    else
        INPUT_FILE="${fasta}"
    fi

    checkv \\
        end_to_end \\
        \$INPUT_FILE \\
        checkv-out \\
        -d $db \\
        -t $task.cpus \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        checkv: \$(checkv -h 2>&1  | sed -n 's/^.*CheckV v//; s/: assessing.*//; 1p')
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    mkdir -p checkv-out
    touch checkv-out/quality_summary.tsv
    touch checkv-out/completeness.tsv
    touch checkv-out/contamination.tsv
    touch checkv-out/complete_genomes.tsv
    touch checkv-out/proviruses.fna
    touch checkv-out/viruses.fna

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        checkv: \$(checkv -h 2>&1  | sed -n 's/^.*CheckV v//; s/: assessing.*//; 1p')
    END_VERSIONS
    """
}
