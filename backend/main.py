
import os
from contextlib import asynccontextmanager

import psycopg
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from psycopg.rows import dict_row

load_dotenv()

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", "5432")),
    "dbname": os.getenv("DB_NAME", "notes_db"),
    "user": os.getenv("DB_USER", "postgres"),
    "password": os.getenv("DB_PASSWORD"),
}


def get_connection():
    if not DB_CONFIG["password"]:
        raise RuntimeError("DB_PASSWORD is not configured")

    return psycopg.connect(**DB_CONFIG, row_factory=dict_row)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Create the notes table when the application starts.
    with get_connection() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS notes (
                id SERIAL PRIMARY KEY,
                content TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

    yield


app = FastAPI(
    title="Notes API",
    description="Backend API for the Notes application",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class NoteCreate(BaseModel):
    content: str = Field(min_length=1, max_length=5000)


@app.get("/")
def root():
    return {"message": "Notes API is running"}


@app.get("/health")
def health():
    try:
        with get_connection() as conn:
            conn.execute("SELECT 1")

        return {
            "status": "ok",
            "database": "connected"
        }
    except Exception:
        raise HTTPException(
            status_code=503,
            detail="Database connection failed"
        )


@app.get("/notes")
def get_notes():
    with get_connection() as conn:
        rows = conn.execute("""
            SELECT id, content
            FROM notes
            ORDER BY created_at DESC
        """).fetchall()

    return rows


@app.post("/notes", status_code=201)
def create_note(note: NoteCreate):
    with get_connection() as conn:
        row = conn.execute("""
            INSERT INTO notes (content)
            VALUES (%s)
            RETURNING id, content
        """, (note.content,)).fetchone()

    return row


@app.delete("/notes/{note_id}")
def delete_note(note_id: int):
    with get_connection() as conn:
        cursor = conn.execute("""
            DELETE FROM notes
            WHERE id = %s
        """, (note_id,))

        if cursor.rowcount == 0:
            raise HTTPException(
                status_code=404,
                detail="Note not found"
            )

    return {"message": "Note deleted successfully"}
