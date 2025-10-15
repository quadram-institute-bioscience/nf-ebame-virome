process EXTRACT_REPSEQ {
    tag "$meta.id"
    label 'process_low'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/seqfu:1.22.3--hfd12232_2':
        'biocontainers/seqfu:1.22.3--hfd12232_2' }"

    input:
    tuple val(meta), path(virus_fasta), path(representative_ids)

    output:
    tuple val(meta), path("vOTU_representatives.fna"), emit: representatives
    path "versions.yml"                               , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Decompress input if needed
    if [[ ${virus_fasta} == *.gz ]]; then
        gunzip -c ${virus_fasta} > input_viruses.fna
        INPUT_FILE="input_viruses.fna"
    else
        INPUT_FILE="${virus_fasta}"
    fi

    # Extract representative sequences using seqfu
    seqfu grep -f ${representative_ids} \$INPUT_FILE > vOTU_representatives.fna

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        seqfu: \$(seqfu version 2>&1 | sed 's/seqfu //')
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch vOTU_representatives.fna

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        seqfu: \$(seqfu version 2>&1 | sed 's/seqfu //')
    END_VERSIONS
    """
}
