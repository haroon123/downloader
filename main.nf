#!/usr/bin/env nextflow

def helpMessage() {
    log.info nfcoreHeader()
    log.info """
    Usage:
    ./main.nf --ega --out_dir="/path/to/downloaded/fastqs" --accession="EGAD000XXXXX"

    --accession_list    List of accession numbers (of files)/download links. One file per line. 
    --accession         Accession number (of a dataset) to download. 

    Download-modes:
    --ega               EGA archive
    --wget              Just download a plain list of ftp/http links
    --sra               Download from SRA

    """.stripIndent()
}

// Show help message
if (params.help) {
    helpMessage()
    exit 0
}

if (params.accession_list  && params.accession) {
    exit 1, "You can only specify either of accession_list or accession"
}


if (params.wget) {
    if(params.accession) {
        exit 1, "wget download mode only supports accession_lists"
    }
    process download_wget {
        publishDir "${params.out_dir}", mode: params.publish_dir_mode
        input:
            val url from Channel.fromPath(params.accession_list).splitText()
        output:
            file "${url.baseName}"

        script:
        """
        wget $url
        """
        
    }
}

if (params.sra) {
    if(params.accession) {
        exit 1, "sra download mode only supports accession_lists"
    }
    process sra_prefetch {
        input:
            val sra_acc from Channel.fromPath(params.accession_list).splitText()
        output:
            tuple val(sra_acc), file("$srr_acc") into sra_prefetch

        script:
        """
        # max size: 1TB
        prefetch --progress 1 --max_size 1024000000 $sra_acc
        """       
    } 

    process sra_dump {
        publishDir "${params.out_dir}", mode: params.publish_dir_mode
        input:
            val(sra_acc), file(prefetch_dir) from sra_prefetch
        
        output:
            "fastq/*.f*q.gz"
        
        script:
        """
        # fastq-dump options according to https://edwards.sdsu.edu/research/fastq-dump/
        fasterq-dump --outidr fastq --gzip --skip-technical --readids \
            --read-filter pass --dumpbase --split-3 --clip SRR_ID --threads ${task.cpus}
        """
    }
}


if(params.ega) {
    if(params.accession) {
        process get_ids {
            conda "envs/pyega.yml"
            publishDir "${params.out_dir}", mode: params.publish_dir_mode
            input:
                val egad_identifier from Channel.value(params.accession)
            output:
                file "egaf_list.txt" into egaf_list

            """
            pyega3 -cf ${params.egaCredFile} files $egad_identifier | grep "^EGAF" | cut -f 1 -d" " > egaf_list.txt
            """
        }
    } else {
        egaf_list = file(params.accession_list)
    }

    process download_fastq {
        conda "envs/pyega.yml"
        errorStrategy { task.attempt <= 2 ? 'retry' : 'ignore' }
        publishDir "${params.out_dir}", mode: params.publish_dir_mode

        input:
            each egaf_identifier from egaf_list.readLines()

        output:
            file "**/*.f*q.gz" into fastqs

        """
        pyega3 -cf ${params.egaCredFile} -c ${params.downloadConnections} fetch $egaf_identifier
        """
    }
}
