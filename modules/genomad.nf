process GENOMAD_ENDTOEND {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/genomad:1.9.0--pyhdfd78af_1':
        'biocontainers/genomad:1.9.0--pyhdfd78af_1' }"

    input:
    tuple val(meta), path(fasta)
    path  genomad_db

    output:
    tuple val(meta), path("genomad-out/*_summary/*_virus.fna.gz")         , emit: virus_fasta
    tuple val(meta), path("genomad-out/*_summary/*_virus_summary.tsv")    , emit: virus_summary
    tuple val(meta), path("genomad-out/*_summary/*_virus_genes.tsv")      , emit: virus_genes
    tuple val(meta), path("genomad-out/*_summary/*_virus_proteins.faa.gz"), emit: virus_proteins
    tuple val(meta), path("genomad-out/*_summary/*_plasmid.fna.gz")       , emit: plasmid_fasta
    tuple val(meta), path("genomad-out/*_summary/*_plasmid_summary.tsv")  , emit: plasmid_summary
    tuple val(meta), path("genomad-out")                                  , emit: genomad_dir
    path "versions.yml"                                                   , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Decompress input if needed
    if [[ ${fasta} == *.gz ]]; then
        gunzip -c ${fasta} > input_assembly.fna
        INPUT_FILE="input_assembly.fna"
    else
        INPUT_FILE="${fasta}"
    fi

    genomad \\
        end-to-end \\
        \$INPUT_FILE \\
        genomad-out \\
        $genomad_db \\
        --threads $task.cpus \\
        $args

    # Compress output files
    gzip genomad-out/*_summary/*.fna
    gzip genomad-out/*_summary/*.faa

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        genomad: \$(echo \$(genomad --version 2>&1) | sed 's/^.*geNomad, version //; s/ .*\$//')
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    mkdir -p genomad-out/${prefix}_summary
    echo "" | gzip > genomad-out/${prefix}_summary/${prefix}_virus.fna.gz
    touch genomad-out/${prefix}_summary/${prefix}_virus_summary.tsv
    touch genomad-out/${prefix}_summary/${prefix}_virus_genes.tsv
    echo "" | gzip > genomad-out/${prefix}_summary/${prefix}_virus_proteins.faa.gz
    echo "" | gzip > genomad-out/${prefix}_summary/${prefix}_plasmid.fna.gz
    touch genomad-out/${prefix}_summary/${prefix}_plasmid_summary.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        genomad: \$(echo \$(genomad --version 2>&1) | sed 's/^.*geNomad, version //; s/ .*\$//')
    END_VERSIONS
    """
}
