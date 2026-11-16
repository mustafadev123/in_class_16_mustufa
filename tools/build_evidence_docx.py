from pathlib import Path
import re
from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.shared import Inches, Pt

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "EVIDENCE_FINAL.md"
OUTPUT = ROOT / "ICA16_A_Mustufa.docx"

def add_inline(paragraph, text):
    for part in re.split(r"(`[^`]+`|\*\*[^*]+\*\*)", text):
        if part.startswith("`") and part.endswith("`"):
            run = paragraph.add_run(part[1:-1]); run.font.name = "Consolas"
        elif part.startswith("**") and part.endswith("**"):
            paragraph.add_run(part[2:-2]).bold = True
        else:
            paragraph.add_run(part)

def build():
    doc = Document()
    doc.styles["Normal"].font.name = "Aptos"
    doc.styles["Normal"].font.size = Pt(10.5)
    lines = SOURCE.read_text(encoding="utf-8").splitlines()
    i, in_code, code_lines = 0, False, []
    while i < len(lines):
        line = lines[i]
        if line.startswith("```"):
            if in_code:
                p = doc.add_paragraph(); run = p.add_run("\n".join(code_lines))
                run.font.name = "Consolas"; run.font.size = Pt(9)
                code_lines, in_code = [], False
            else: in_code = True
            i += 1; continue
        if in_code:
            code_lines.append(line); i += 1; continue
        if line.startswith("|"):
            table_lines = []
            while i < len(lines) and lines[i].startswith("|"):
                table_lines.append(lines[i]); i += 1
            rows = [r for n, r in enumerate(table_lines) if n != 1]
            cells = [[c.strip() for c in r.strip("|").split("|")] for r in rows]
            table = doc.add_table(rows=len(cells), cols=len(cells[0])); table.style = "Table Grid"
            for rn, row in enumerate(cells):
                for cn, value in enumerate(row):
                    table.cell(rn, cn).text = value
                    if rn == 0:
                        for run in table.cell(rn, cn).paragraphs[0].runs: run.bold = True
            continue
        image = re.match(r"!\[(.*?)\]\((.*?)\)", line)
        if image:
            path = ROOT / image.group(2)
            if path.exists():
                p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
                p.add_run().add_picture(str(path), width=Inches(3.1))
                cap = doc.add_paragraph(image.group(1)); cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
                if cap.runs: cap.runs[0].italic = True
            i += 1; continue
        if line.startswith("# "): doc.add_heading(line[2:], 0)
        elif line.startswith("## "): doc.add_heading(line[3:], 1)
        elif line.startswith("### "): doc.add_heading(line[4:], 2)
        elif line.startswith("- [x] "): doc.add_paragraph("☒ " + line[6:], style="List Bullet")
        elif line.startswith("- [ ] "): doc.add_paragraph("☐ " + line[6:], style="List Bullet")
        elif line.startswith("- "):
            p = doc.add_paragraph(style="List Bullet"); add_inline(p, line[2:])
        elif line.strip():
            p = doc.add_paragraph(); add_inline(p, line)
        i += 1
    section = doc.sections[0]
    section.top_margin = section.bottom_margin = Inches(0.65)
    section.left_margin = section.right_margin = Inches(0.7)
    doc.save(OUTPUT); print(OUTPUT)

if __name__ == "__main__": build()
