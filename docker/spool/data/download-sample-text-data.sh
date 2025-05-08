#!/bin/bash

# Number of books to download (default 10)
NUM_BOOKS=${1:-10}

# List of book URLs (can be extended)
BOOK_URLS=(
  "https://www.gutenberg.org/files/1342/1342-0.txt"  # Pride and Prejudice
  "https://www.gutenberg.org/files/11/11-0.txt"      # Alice's Adventures in Wonderland
  "https://www.gutenberg.org/files/84/84-0.txt"      # Frankenstein
  "https://www.gutenberg.org/files/98/98-0.txt"      # A Tale of Two Cities
  "https://www.gutenberg.org/files/2701/2701-0.txt"  # Moby Dick
  "https://www.gutenberg.org/files/120/120-0.txt"    # Innocents Abroad
  "https://www.gutenberg.org/files/1661/1661-0.txt"  # Sherlock Holmes
  "https://www.gutenberg.org/files/74/74-0.txt"      # Tom Sawyer
  "https://www.gutenberg.org/files/2542/2542-0.txt"  # A Doll's House
  "https://www.gutenberg.org/files/2600/2600-0.txt"  # War and Peace
)

mkdir -p gutenberg_sample

echo "📚 Downloading $NUM_BOOKS sample books from Project Gutenberg..."
for ((i=0; i<NUM_BOOKS && i<${#BOOK_URLS[@]}; i++)); do
  url="${BOOK_URLS[$i]}"
  filename=$(basename "$url")
  echo "⬇️  Downloading $filename..."
  curl -s "$url" -o "gutenberg_sample/$filename"
done
