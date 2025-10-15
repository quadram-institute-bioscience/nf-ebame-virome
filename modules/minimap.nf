process MINIMAP2_ALIGN {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://community-cr-prod.seqera.io/docker/registry/v2/blobs/sha256/66/66dc96eff11ab80dfd5c044e9b3425f52d818847b9c074794cf0c02bfa781661/data' :
        'community.wave.seqera.io/library/minimap2_samtools:33bb43c18d22e29c' }"

    input:
    tuple val(meta), path(reads), val(meta2), path(reference)
    val bam_format
    val bam_index_extension
    val cigar_paf_format
    val cigar_bam

    output:
    tuple val(meta), path("*.bam")                       , optional: true, emit: bam
    tuple val(meta), path("*.bam.${bam_index_extension}"), optional: true, emit: index
    path "versions.yml"                                  , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args  = task.ext.args ?: '-ax sr'
    def prefix = task.ext.prefix ?: "${meta.id}"
    def bam_index = bam_index_extension ? "${prefix}.bam##idx##${prefix}.bam.${bam_index_extension} --write-index" : "${prefix}.bam"
    """
    # Decompress reference if needed
    if [[ ${reference} == *.gz ]]; then
        gunzip -c ${reference} > reference.fna
        REF_FILE="reference.fna"
    else
        REF_FILE="${reference}"
    fi

    minimap2 \\
        $args \\
        -t $task.cpus \\
        \$REF_FILE \\
        ${reads[0]} \\
        ${reads[1]} \\
        | samtools sort -@ ${task.cpus-1} -o ${bam_index}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        minimap2: \$(minimap2 --version 2>&1)
        samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def output_file = "${prefix}.bam"
    def bam_index = bam_index_extension ? "touch ${prefix}.bam.${bam_index_extension}" : ""
    """
    touch $output_file
    ${bam_index}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        minimap2: \$(minimap2 --version 2>&1)
        samtools: \$(echo \$(samtools --version 2>&1) | sed 's/^.*samtools //; s/Using.*\$//')
    END_VERSIONS
    """
}
