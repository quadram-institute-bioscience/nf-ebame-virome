process DEREPLICATE {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/checkv:1.0.3--pyhdfd78af_0':
        'biocontainers/checkv:1.0.3--pyhdfd78af_0' }"

    input:
    tuple val(meta), path(virus_fasta), path(quality_summary)

    output:
    tuple val(meta), path("vOTU_clusters.tsv")           , emit: clusters
    tuple val(meta), path("vOTU_representatives.txt")    , emit: representative_ids
    tuple val(meta), path("genomad_ani.tsv")             , emit: ani
    path "versions.yml"                                  , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def min_ani = task.ext.min_ani ?: 95
    def min_tcov = task.ext.min_tcov ?: 85
    def min_qcov = task.ext.min_qcov ?: 0
    """
    # Decompress input if needed
    if [[ ${virus_fasta} == *.gz ]]; then
        gunzip -c ${virus_fasta} > input_viruses.fna
        INPUT_FILE="input_viruses.fna"
    else
        INPUT_FILE="${virus_fasta}"
    fi

    # Step 1: Create BLAST database
    makeblastdb \\
        -in \$INPUT_FILE \\
        -dbtype nucl \\
        -out genomad_votus_db

    # Step 2: All-vs-all BLAST
    blastn \\
        -query \$INPUT_FILE \\
        -db genomad_votus_db \\
        -outfmt '6 std qlen slen' \\
        -max_target_seqs 10000 \\
        -num_threads $task.cpus \\
        -out genomad_blast.tsv

    # Step 3: Calculate pairwise ANI
    # The anicalc.py script should be in the bin/ directory and exposed by Nextflow
    anicalc.py \\
        -i genomad_blast.tsv \\
        -o genomad_ani.tsv

    # Step 4: Cluster sequences
    # The aniclust.py script should be in the bin/ directory and exposed by Nextflow
    aniclust.py \\
        --fna \$INPUT_FILE \\
        --ani genomad_ani.tsv \\
        --out vOTU_clusters.tsv \\
        --min_ani $min_ani \\
        --min_tcov $min_tcov \\
        --min_qcov $min_qcov

    # Step 5: Extract representative IDs
    awk '{print \$1}' vOTU_clusters.tsv > vOTU_representatives.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        blast: \$(blastn -version 2>&1 | sed 's/^.*blastn: //; s/ .*\$//')
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch vOTU_clusters.tsv
    touch vOTU_representatives.txt
    touch genomad_ani.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        blast: \$(blastn -version 2>&1 | sed 's/^.*blastn: //; s/ .*\$//')
    END_VERSIONS
    """
}
