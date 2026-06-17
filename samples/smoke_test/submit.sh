#!/usr/bin/env bash
# Submit the sample chapter PDF to the Question Generation v1.0 form trigger.
#
# Required environment:
#   N8N_BASE_URL           e.g. https://devvrat.app.n8n.cloud
#   N8N_FORM_PATH          form trigger webhook path (find in the n8n UI after activating the workflow;
#                          looks like /form/<uuid>)
#
# Optional environment (defaults shown):
#   BOARD=CBSE  CLASS=12  SUBJECT=Chemistry  CHAPTER="Solutions"
#   SOURCE_TYPE=NCERT  QUESTION_TYPE=MCQ  DIFFICULTY=Intermediate
#   NUM_QUESTIONS=10  LANGUAGE=en  INCLUDE_VISUALS=false

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PDF="${HERE}/sample_chapter_solutions.pdf"

if [[ ! -f "$PDF" ]]; then
  echo "PDF missing. Generate it first:" >&2
  echo "  python3 ${HERE}/generate_sample_pdf.py" >&2
  exit 1
fi

: "${N8N_BASE_URL:?Set N8N_BASE_URL (e.g. https://devvrat.app.n8n.cloud)}"
: "${N8N_FORM_PATH:?Set N8N_FORM_PATH (e.g. /form/<uuid> from the n8n UI)}"

BOARD="${BOARD:-CBSE}"
CLASS="${CLASS:-12}"
SUBJECT="${SUBJECT:-Chemistry}"
CHAPTER="${CHAPTER:-Solutions}"
SOURCE_TYPE="${SOURCE_TYPE:-NCERT}"
QUESTION_TYPE="${QUESTION_TYPE:-MCQ}"
DIFFICULTY="${DIFFICULTY:-Intermediate}"
NUM_QUESTIONS="${NUM_QUESTIONS:-10}"
LANGUAGE="${LANGUAGE:-en}"
INCLUDE_VISUALS="${INCLUDE_VISUALS:-false}"

URL="${N8N_BASE_URL%/}${N8N_FORM_PATH}"

echo "POST  ${URL}"
echo "      board=${BOARD} class=${CLASS} subject=${SUBJECT} chapter=${CHAPTER}"
echo "      qtype=${QUESTION_TYPE} difficulty=${DIFFICULTY} n=${NUM_QUESTIONS}"
echo

curl -sS -X POST "${URL}" \
  -F "board=${BOARD}" \
  -F "class=${CLASS}" \
  -F "subject=${SUBJECT}" \
  -F "chapter_name=${CHAPTER}" \
  -F "source_type=${SOURCE_TYPE}" \
  -F "question_type=${QUESTION_TYPE}" \
  -F "difficulty_level=${DIFFICULTY}" \
  -F "number_of_questions=${NUM_QUESTIONS}" \
  -F "language=${LANGUAGE}" \
  -F "include_visual_questions=${INCLUDE_VISUALS}" \
  -F "reference_pdf=@${PDF};type=application/pdf" \
  | tee /tmp/qgen_submit_response.json

echo
echo
echo "Response saved to /tmp/qgen_submit_response.json"
echo "Pick the batch_id from the response and run verify.sh BATCH=<batch_id>"
