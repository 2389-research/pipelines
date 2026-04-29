#!/bin/bash
# Standalone test of the proposed patch_file flow — validation, retry-with-feedback, git rollback.
# Runs qwen against a known-good file with a clear append task.
# Exits 0 if qwen produces a validated output within the retry budget.

set -eu

QWEN_MODEL="${QWEN_MODEL:-qwen3.6:35b-a3b-q8_0}"
OLLAMA="${OLLAMA:-http://localhost:11434/api/chat}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-5}"

TEST_DIR=$(mktemp -d -t patch-flow-XXXXX)
trap "echo; echo 'Test dir: $TEST_DIR (preserved for inspection)'" EXIT

echo "═══ Setup ═══"
echo "Test dir: $TEST_DIR"

# Known-good baseline — what sprint 001 would have produced for models.py
cat > "$TEST_DIR/models.py" <<'EOF'
import uuid
from datetime import datetime
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy import String, DateTime, func


class Base(DeclarativeBase):
    pass


class Volunteer(Base):
    __tablename__ = "volunteers"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    email: Mapped[str] = mapped_column(String, unique=True, index=True)
    phone: Mapped[str] = mapped_column(String, unique=True, index=True)
    name: Mapped[str] = mapped_column(String)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class OTP(Base):
    __tablename__ = "otps"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    phone: Mapped[str] = mapped_column(String, index=True)
    code: Mapped[str] = mapped_column(String(6))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
EOF

# Init git so rollback works
cd "$TEST_DIR"
git init -q
git -c user.email=t@l -c user.name=t add -A
git -c user.email=t@l -c user.name=t commit -qm "good baseline"

PRE_LINES=$(wc -l < models.py | tr -d ' ')
PRE_CLASSES=$(grep -cE '^class ' models.py)
echo "Baseline: $PRE_LINES lines, $PRE_CLASSES classes (Base, Volunteer, OTP)"

# Per-file spec slice — describes the modification (a 'Modified files' bullet expanded)
SPEC='This is the existing models.py for a FastAPI backend. APPEND the following NEW classes after the existing OTP model. Do NOT remove or modify the existing Base, Volunteer, or OTP classes — they must remain exactly as-is.

NEW classes to append:

class Location(Base):
    __tablename__ = "locations"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String)
    address: Mapped[str] = mapped_column(String)

class Station(Base):
    __tablename__ = "stations"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    location_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("locations.id"))
    name: Mapped[str] = mapped_column(String)
    max_capacity: Mapped[int] = mapped_column(Integer)

You will need to add these imports if not already present:
- from sqlalchemy import ForeignKey, Integer

Output the COMPLETE updated file (existing classes + new imports + new classes). Output raw Python only — no fences, no commentary.'

EXPECTED_NEW_CLASSES="Location Station"

call_qwen() {
  local user_msg="$1"
  curl -sf "$OLLAMA" \
    -H 'Content-Type: application/json' \
    --data "$(jq -n \
      --arg sys 'You are a code editor. Output the complete updated file content. No explanation, no markdown fences, no commentary.' \
      --arg msg "$user_msg" \
      --arg model "$QWEN_MODEL" \
      '{model:$model,think:false,stream:false,
        messages:[{role:"system",content:$sys},{role:"user",content:$msg}],
        options:{temperature:0.2,num_ctx:32768}}')" \
    | jq -r '.message.content' \
    | sed '/^```/d'
}

validate_output() {
  local file="$1"
  local errors=""

  # Guard 1: line-count floor (>=80% of pre)
  local post_lines floor
  post_lines=$(wc -l < "$file" | tr -d ' ')
  floor=$((PRE_LINES * 80 / 100))
  if [ "$post_lines" -lt "$floor" ]; then
    errors="$errors LINE_COUNT_DROP(post=$post_lines pre=$PRE_LINES floor=$floor)"
  fi

  # Guard 2: symbol preservation — every pre-edit class must still be present
  for sym in Base Volunteer OTP; do
    grep -qE "^class ${sym}\b" "$file" || errors="$errors MISSING_PRE_SYMBOL($sym)"
  done

  # Guard 3: spec-promised new symbols present
  for sym in $EXPECTED_NEW_CLASSES; do
    grep -qE "^class ${sym}\b" "$file" || errors="$errors MISSING_NEW_SYMBOL($sym)"
  done

  # Guard 4: syntax (parse-time)
  python3 -m py_compile "$file" 2>/dev/null || errors="$errors SYNTAX_ERROR"

  echo "$errors"
}

feedback=""
for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
  echo
  echo "═══ Attempt $attempt/$MAX_ATTEMPTS ═══"

  # Rebuild user prompt each iteration; rollback before retry
  if [ "$attempt" -gt 1 ]; then
    git checkout HEAD -- models.py
    echo "rolled back to baseline"
  fi
  current=$(cat models.py)

  user_msg="EXISTING FILE: models.py

\`\`\`python
$current
\`\`\`

$SPEC$feedback"

  echo "calling qwen..."
  fixed=$(call_qwen "$user_msg")

  candidate="models.py.candidate"
  printf '%s' "$fixed" > "$candidate"

  errors=$(validate_output "$candidate")

  if [ -z "$errors" ]; then
    mv "$candidate" models.py
    echo "✓ validation passed on attempt $attempt"
    echo
    echo "═══ Final state ═══"
    grep -E '^class ' models.py
    POST_LINES=$(wc -l < models.py | tr -d ' ')
    POST_CLASSES=$(grep -cE '^class ' models.py)
    echo "$PRE_LINES → $POST_LINES lines, $PRE_CLASSES → $POST_CLASSES classes"
    exit 0
  fi

  echo "✗ validation failed:$errors"
  rm -f "$candidate"
  feedback="

PREVIOUS ATTEMPT FAILED VALIDATION:$errors

Common causes: (1) you removed an existing class — they must all stay; (2) you returned just a partial file — output the COMPLETE file with imports, all existing classes, and the new classes; (3) you used markdown fences — emit raw Python only. Fix these issues and output the COMPLETE updated file."
done

echo
echo "═══ Exhausted $MAX_ATTEMPTS attempts — escalation point ═══"
exit 1
