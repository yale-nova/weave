#!/bin/bash 


time spark-submit --class org.apache.spark.shuffle.examples.SparkWordCountApp /opt/spark/jars/spark-weave-shuffle-assembly-0.1.0.jar /workspace/data/beyond-the-pleasure-principle.txt spark


time spark-submit --class org.apache.spark.shuffle.examples.SparkWordCountApp /opt/spark/jars/spark-weave-shuffle-assembly-0.1.0.jar /workspace/data/beyond-the-pleasure-principle.txt weave


time spark-submit --class org.apache.spark.shuffle.examples.SparkWordCountApp /opt/spark/jars/spark-weave-shuffle-assembly-0.1.0.jar /workspace/data/beyond-the-pleasure-principle.txt columnsort
