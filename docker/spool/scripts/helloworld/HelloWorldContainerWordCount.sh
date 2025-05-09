#!/bin/bash 


time spark-submit --class org.apache.spark.shuffle.examples.SparkWordCountApp /opt/spark/jars/spark-weave-shuffle_2.12-0.1.0.jar /opt/spark/enclave/data/beyond-the-pleasure-principle.txt spark


time spark-submit --class org.apache.spark.shuffle.examples.SparkWordCountApp /opt/spark/jars/spark-weave-shuffle_2.12-0.1.0.jar /opt/spark/enclave/data/beyond-the-pleasure-principle.txt weave


time spark-submit --class org.apache.spark.shuffle.examples.SparkWordCountApp /opt/spark/jars/spark-weave-shuffle_2.12-0.1.0.jar /opt/spark/enclave/data/beyond-the-pleasure-principle.txt columnsort
