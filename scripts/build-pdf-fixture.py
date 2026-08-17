#!/usr/bin/env python3
"""Build the original multi-page PDF fixture used by tests and demos."""

from pathlib import Path

from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import A4
from reportlab.pdfgen.canvas import Canvas


PROJECT_DIR = Path(__file__).resolve().parent.parent
OUTPUT = PROJECT_DIR / "eval" / "fixtures" / "north-star-invoice.pdf"
WIDTH, HEIGHT = A4
INK = HexColor("#172033")
MUTED = HexColor("#64748B")
PURPLE = HexColor("#7C3AED")
GREEN = HexColor("#16A34A")
PALE = HexColor("#F5F3FF")
LINE = HexColor("#D8DEE9")


def header(canvas: Canvas, page_title: str, page_number: int) -> None:
    canvas.setFillColor(INK)
    canvas.setFont("Helvetica-Bold", 18)
    canvas.drawString(48, HEIGHT - 54, "NORTH STAR STUDIO")
    canvas.setFillColor(MUTED)
    canvas.setFont("Helvetica", 9)
    canvas.drawString(48, HEIGHT - 70, "Original synthetic fixture for Image Autonamer")

    canvas.setFillColor(PALE)
    canvas.roundRect(WIDTH - 178, HEIGHT - 72, 130, 28, 8, fill=1, stroke=0)
    canvas.setFillColor(PURPLE)
    canvas.setFont("Helvetica-Bold", 9)
    canvas.drawCentredString(WIDTH - 113, HEIGHT - 61, "ORIGINAL TEST FIXTURE")

    canvas.setStrokeColor(LINE)
    canvas.line(48, HEIGHT - 88, WIDTH - 48, HEIGHT - 88)
    canvas.setFillColor(INK)
    canvas.setFont("Helvetica-Bold", 24)
    canvas.drawString(48, HEIGHT - 128, page_title)
    canvas.setFillColor(MUTED)
    canvas.setFont("Helvetica", 9)
    canvas.drawRightString(WIDTH - 48, 34, f"Page {page_number} of 3")
    canvas.drawString(48, 34, "Synthetic sample. No real customer, account, or transaction.")


def label_value(canvas: Canvas, x: float, y: float, label: str, value: str) -> None:
    canvas.setFillColor(MUTED)
    canvas.setFont("Helvetica-Bold", 8)
    canvas.drawString(x, y, label.upper())
    canvas.setFillColor(INK)
    canvas.setFont("Helvetica", 11)
    canvas.drawString(x, y - 16, value)


def page_one(canvas: Canvas) -> None:
    header(canvas, "INVOICE", 1)
    label_value(canvas, 48, HEIGHT - 174, "Invoice number", "INV-2048")
    label_value(canvas, 214, HEIGHT - 174, "Issue date", "2026-08-15")
    label_value(canvas, 380, HEIGHT - 174, "Due date", "2026-09-14")

    canvas.setFillColor(PALE)
    canvas.roundRect(48, HEIGHT - 294, WIDTH - 96, 72, 10, fill=1, stroke=0)
    label_value(canvas, 66, HEIGHT - 246, "Bill to", "Cedar Workshop")
    canvas.setFillColor(MUTED)
    canvas.setFont("Helvetica", 9)
    canvas.drawString(66, HEIGHT - 278, "Website refresh and launch support")

    top = HEIGHT - 338
    columns = [(48, "DESCRIPTION"), (350, "QTY"), (420, "RATE"), (WIDTH - 48, "AMOUNT")]
    canvas.setFillColor(INK)
    canvas.setFont("Helvetica-Bold", 8)
    for x, title in columns:
        if title == "AMOUNT":
            canvas.drawRightString(x, top, title)
        else:
            canvas.drawString(x, top, title)
    canvas.setStrokeColor(LINE)
    canvas.line(48, top - 10, WIDTH - 48, top - 10)

    rows = [
        ("Product design sprint", "1", "EUR 720.00", "EUR 720.00"),
        ("Interface implementation", "8", "EUR 72.00", "EUR 576.00"),
        ("Launch checklist and handoff", "1", "EUR 132.00", "EUR 132.00"),
    ]
    y = top - 42
    canvas.setFont("Helvetica", 10)
    for description, quantity, rate, amount in rows:
        canvas.setFillColor(INK)
        canvas.drawString(48, y, description)
        canvas.drawString(350, y, quantity)
        canvas.drawString(420, y, rate)
        canvas.drawRightString(WIDTH - 48, y, amount)
        canvas.setStrokeColor(LINE)
        canvas.line(48, y - 14, WIDTH - 48, y - 14)
        y -= 48

    canvas.setFillColor(INK)
    canvas.setFont("Helvetica-Bold", 11)
    canvas.drawString(350, y - 4, "TOTAL")
    canvas.setFillColor(GREEN)
    canvas.setFont("Helvetica-Bold", 16)
    canvas.drawRightString(WIDTH - 48, y - 5, "EUR 1,428.00")

    canvas.setFillColor(MUTED)
    canvas.setFont("Helvetica", 9)
    canvas.drawString(48, 92, "Thank you for supporting independent, privacy-first software.")


def page_two(canvas: Canvas) -> None:
    header(canvas, "DELIVERY SUMMARY", 2)
    canvas.setFillColor(MUTED)
    canvas.setFont("Helvetica", 11)
    canvas.drawString(48, HEIGHT - 160, "Work completed for invoice INV-2048")

    items = [
        ("01", "Research synthesis", "Interview themes converted into a focused launch brief."),
        ("02", "Product design", "Responsive settings and review workflows prepared for implementation."),
        ("03", "Engineering handoff", "Acceptance criteria, edge cases, and release checks documented."),
    ]
    y = HEIGHT - 222
    for number, title, body in items:
        canvas.setFillColor(PURPLE)
        canvas.setFont("Helvetica-Bold", 11)
        canvas.drawString(48, y, number)
        canvas.setFillColor(INK)
        canvas.setFont("Helvetica-Bold", 13)
        canvas.drawString(86, y, title)
        canvas.setFillColor(MUTED)
        canvas.setFont("Helvetica", 10)
        canvas.drawString(86, y - 20, body)
        canvas.setStrokeColor(LINE)
        canvas.line(86, y - 42, WIDTH - 48, y - 42)
        y -= 92


def page_three(canvas: Canvas) -> None:
    header(canvas, "PAYMENT NOTES", 3)
    canvas.setFillColor(INK)
    canvas.setFont("Helvetica-Bold", 13)
    canvas.drawString(48, HEIGHT - 174, "Reference")
    canvas.setFont("Helvetica", 11)
    canvas.drawString(48, HEIGHT - 196, "Use invoice reference INV-2048 with payment.")

    canvas.setFont("Helvetica-Bold", 13)
    canvas.drawString(48, HEIGHT - 248, "Terms")
    canvas.setFont("Helvetica", 11)
    canvas.drawString(48, HEIGHT - 270, "Payment is due within 30 days of the issue date.")

    canvas.setFillColor(PALE)
    canvas.roundRect(48, HEIGHT - 402, WIDTH - 96, 88, 10, fill=1, stroke=0)
    canvas.setFillColor(PURPLE)
    canvas.setFont("Helvetica-Bold", 12)
    canvas.drawString(66, HEIGHT - 342, "Privacy note")
    canvas.setFillColor(INK)
    canvas.setFont("Helvetica", 10)
    canvas.drawString(66, HEIGHT - 364, "This PDF contains invented names, references, dates, and amounts.")
    canvas.drawString(66, HEIGHT - 382, "It is released under the repository's MIT license for demos and tests.")


def main() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    canvas = Canvas(str(OUTPUT), pagesize=A4, pageCompression=1, invariant=1)
    canvas.setTitle("North Star Studio synthetic invoice")
    canvas.setAuthor("Image Autonamer contributors")
    for draw_page in (page_one, page_two, page_three):
        draw_page(canvas)
        canvas.showPage()
    canvas.save()
    print(f"Built {OUTPUT}")


if __name__ == "__main__":
    main()
