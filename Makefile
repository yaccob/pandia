SRC      := example.md
FILTER   := diagram-filter.lua
PDF      := $(SRC:.md=.pdf)
HTML     := $(SRC:.md=.html)
IMGDIR   := img
IMAGE    := yaccob/pandia
VERSION  := 1.2.1

PANDOC_COMMON := --lua-filter=$(FILTER) --from=gfm+tex_math_dollars

.PHONY: all pdf html clean docker-pdf docker-html docker-all docker-build docker-push

# --- Local targets (require pandoc + tools installed) ---

all: pdf html

pdf: $(PDF)
html: $(HTML)

$(PDF): $(SRC) $(FILTER)
	pandoc $(PANDOC_COMMON) \
		--to=pdf \
		--pdf-engine=pdflatex \
		-V geometry:margin=2.5cm \
		-V mainfont="Helvetica" \
		-V classoption=fleqn \
		--standalone \
		-o $@ $<

$(HTML): $(SRC) $(FILTER)
	pandoc $(PANDOC_COMMON) \
		--to=html5 \
		--standalone \
		--mathjax \
		-V maxwidth=60em \
		-V "header-includes=<script>window.MathJax={chtml:{displayAlign:'left'}};</script>" \
		--metadata title="Markdown with Diagrams and Formulas" \
		-o $@ $<

clean:
	rm -rf $(PDF) $(HTML) $(IMGDIR)

# --- Docker targets ---

docker-pdf:
	docker run --rm -v "$$PWD:/data" $(IMAGE) --pdf $(SRC)

docker-html:
	docker run --rm -v "$$PWD:/data" $(IMAGE) --html $(SRC)

docker-all:
	docker run --rm -v "$$PWD:/data" $(IMAGE) --all $(SRC)

docker-build:
	docker build -t $(IMAGE):$(VERSION) -t $(IMAGE):latest .

docker-push: docker-build
	docker push $(IMAGE):$(VERSION)
	docker push $(IMAGE):latest
