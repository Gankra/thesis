#!/bin/bash

# Create .aux files
pdflatex -shell-escape thesis.tex

# Run BibTeX on all chapters
cd chapters

# Clean up old files
rm *.bbl
rm *.blg

for f in *.aux
do
 bibtex "$f"
done

# Compile the main file twice more
cd ..
pdflatex -shell-escape thesis.tex
pdflatex -shell-escape thesis.tex
