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
    tuple val(meta), path("vOTUs.fa"), emit: representatives
    tuple val(meta), path("vOTU_names.tsv"), emit: table
    path "versions.yml"                               , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Extract representative sequences using seqfu list
    # seqfu can read compressed files directly
    seqfu list ${representative_ids} ${virus_fasta} > vOTUs_representatives.fa
    seqfu cat --anvio vOTUs_representatives.fa > vOTUs.fa
    
    seqfu cat --list vOTUs_representatives.fa > original_names.txt
    seqfu cat --list vOTUs.fa                 > new_names.txt

    paste original_names.txt new_names.txt > vOTU_names.tsv
    
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        seqfu: \$(seqfu version 2>&1 | sed 's/seqfu //')
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch vOTUs_representatives.fa

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        seqfu: \$(seqfu version 2>&1 | sed 's/seqfu //')
    END_VERSIONS
    """
}
