REM Create .aux files
pdflatex thesis.tex

REM Run BibTeX on all chapters
cd chapters

REM Clean up old files
del *.bbl
del *.blg

for %%f in (.\*.aux) do (
    bibtex %%f
)

REM Compile the main file twice more
cd ..
pdflatex thesis.tex
pdflatex thesis.tex