process VOTUDEREP {
    tag "$meta.id"
    label 'process_high'

    conda "bioconda::votuderep=0.6.1 bioconda::blast=2.17.0"
    container "${ workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/votuderep%3A0.6.1--pyhdfd78af_0':
        'quay.io/biocontainers/votuderep:0.6.1--pyhdfd78af_0' }"

    input:
    tuple val(meta), path(virus_fasta), path(quality_summary)

    output:
    tuple val(meta), path("dereplicated_vOTUs.fasta"), emit: fasta
    tuple val(meta), path("vOTU_representatives.txt"), emit: representative_ids
    path "versions.yml"                              , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def min_ani = task.ext.min_ani ?: 95
    def min_tcov = task.ext.min_tcov ?: 85
    def min_quality = task.ext.min_quality ?: 'all'
    """
    # Decompress input if needed
    if [[ ${virus_fasta} == *.gz ]]; then
        gunzip -c ${virus_fasta} > input_viruses.fna
        INPUT_FILE="input_viruses.fna"
    else
        INPUT_FILE="${virus_fasta}"
    fi

    # Optionally keep only contigs at or above a CheckV quality tier.
    # The default ("all") retains every geNomad virus, including
    # "Not-determined" contigs, and performs no filtering.
    if [[ "${min_quality}" != "all" ]]; then
        awk -F'\\t' -v min="${min_quality}" '
        BEGIN {
            quality_rank["Complete"] = 4
            quality_rank["High-quality"] = 3
            quality_rank["Medium-quality"] = 2
            quality_rank["Low-quality"] = 1
            quality_rank["Not-determined"] = 0
            min_rank["all"] = -1
            min_rank["low"] = 1
            min_rank["medium"] = 2
            min_rank["high"] = 3
            min_rank["complete"] = 4
            if (!(min in min_rank)) {
                print "ERROR: invalid checkv_min_quality: " min > "/dev/stderr"
                exit 1
            }
            threshold = min_rank[min]
        }
        NR == 1 {
            for (i = 1; i <= NF; i++) {
                if (\$i == "contig_id") id_col = i
                if (\$i == "checkv_quality") quality_col = i
            }
            if (!id_col || !quality_col) {
                print "ERROR: CheckV quality summary lacks contig_id or checkv_quality" > "/dev/stderr"
                exit 1
            }
            next
        }
        quality_rank[\$quality_col] >= threshold {
            id = \$id_col
            sub(/[ \\t].*/, "", id)
            print id
        }
        ' "${quality_summary}" > kept_ids.txt

        if [[ ! -s kept_ids.txt ]]; then
            echo "ERROR: no contigs passed checkv_min_quality=${min_quality}" >&2
            exit 1
        fi

        awk 'NR == FNR { keep[\$0] = 1; next }
             /^>/ { header = substr(\$0, 2); sub(/[ \\t].*/, "", header); keep_record = (header in keep) }
             keep_record { print }' \\
            kept_ids.txt "\$INPUT_FILE" > filtered_viruses.fna

        INPUT_FILE="filtered_viruses.fna"
    fi

    # Dereplicate with votuderep (longest sequence per ANI cluster is retained)
    votuderep derep \\
        -i \$INPUT_FILE \\
        -o dereplicated_vOTUs.fasta \\
        -t $task.cpus \\
        --tmp . \\
        --min-ani $min_ani \\
        --min-tcov $min_tcov \\
        $args

    # votuderep writes only the representative FASTA; derive IDs for EXTRACT_REPSEQ
    grep '^>' dereplicated_vOTUs.fasta | sed 's/^>//; s/[[:space:]].*//' > vOTU_representatives.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        votuderep: \$(votuderep --version 2>&1 | sed 's/^.*version //; s/ .*\$//')
        blast: \$(blastn -version 2>&1 | sed 's/^.*blastn: //; s/ .*\$//')
    END_VERSIONS
    """

    stub:
    """
    touch dereplicated_vOTUs.fasta
    touch vOTU_representatives.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        votuderep: 0.6.1
        blast: 2.17.0
    END_VERSIONS
    """
}
