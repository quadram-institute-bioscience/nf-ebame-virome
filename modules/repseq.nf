process EXTRACT_REPSEQ {
    tag "$meta.id"
    label 'process_low'

    conda "bioconda::seqfu=1.22.3"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/seqfu:1.22.3--hfd12232_2':
        'biocontainers/seqfu:1.22.3--hfd12232_2' }"

    input:
    tuple val(meta), path(virus_fasta), path(representative_ids), path(quality_summary)

    output:
    tuple val(meta), path("vOTUs.fa"), emit: representatives
    tuple val(meta), path("vOTU_names.tsv"), emit: table
    tuple val(meta), path("vOTU_quality.tsv"), emit: quality
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

    # Add the CheckV quality of each representative contig to the vOTU table
    awk -F'\\t' 'BEGIN { OFS = "\\t"; print "original_name", "vOTU", "checkv_quality", "completeness", "contamination" }
    FILENAME == ARGV[1] {
        if (FNR == 1) {
            for (i = 1; i <= NF; i++) {
                if (\$i == "contig_id") id_col = i
                else if (\$i == "checkv_quality") quality_col = i
                else if (\$i == "completeness") completeness_col = i
                else if (\$i == "contamination") contamination_col = i
            }
            next
        }
        id = \$id_col
        sub(/[ \\t].*/, "", id)
        quality[id] = (quality_col ? \$quality_col : "NA")
        completeness[id] = (completeness_col ? \$completeness_col : "NA")
        contamination[id] = (contamination_col ? \$contamination_col : "NA")
        next
    }
    {
        id = \$1
        sub(/[ \\t].*/, "", id)
        q = (id in quality) ? quality[id] : "NA"
        c = (id in completeness) ? completeness[id] : "NA"
        t = (id in contamination) ? contamination[id] : "NA"
        print \$1, \$2, q, c, t
    }
    ' "${quality_summary}" vOTU_names.tsv > vOTU_quality.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        seqfu: \$(seqfu version 2>&1 | sed 's/seqfu //')
    END_VERSIONS
    """

    stub:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch vOTUs.fa
    touch vOTU_names.tsv
    touch vOTU_quality.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        seqfu: \$(seqfu version 2>&1 | sed 's/seqfu //')
    END_VERSIONS
    """
}
