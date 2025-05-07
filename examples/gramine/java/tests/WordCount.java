// SPDX-License-Identifier: BSD-3-Clause

import java.io.*;
import java.nio.file.*;
import java.util.*;

public class WordCount {
    public static void main(String[] args) throws IOException {
        // Use default files if none provided
        String inputFile = args.length > 0 ? args[0] : "data/input.txt";
        String outputFile = args.length > 1 ? args[1] : "output-data/output.txt";

        Map<String, Integer> wordCounts = new HashMap<>();

        try (BufferedReader reader = Files.newBufferedReader(Paths.get(inputFile))) {
            String line;
            while ((line = reader.readLine()) != null) {
                for (String word : line.trim().split("\\s+")) {
                    if (!word.isEmpty()) {
                        word = word.toLowerCase().replaceAll("[^a-z0-9]", "");
                        wordCounts.put(word, wordCounts.getOrDefault(word, 0) + 1);
                    }
                }
            }
        }

        List<String> sortedWords = new ArrayList<>(wordCounts.keySet());
        Collections.sort(sortedWords);

        try (BufferedWriter writer = Files.newBufferedWriter(Paths.get(outputFile))) {
            for (String word : sortedWords) {
                writer.write(word + ": " + wordCounts.get(word));
                writer.newLine();
            }
        }

        System.out.println("Word count completed: " + wordCounts.size() + " unique words.");
    }
}

