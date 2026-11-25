
"use client";

import { useEffect, useState } from "react";

interface Note {
  id: number;
  content: string;
}

const API_URL =
  process.env.NEXT_PUBLIC_API_URL || "";

export default function Home() {
  const [notes, setNotes] = useState<Note[]>([]);
  const [content, setContent] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  const fetchNotes = async () => {
    try {
      const response = await fetch(`${API_URL}/notes`);

      if (!response.ok) throw new Error("Unable to fetch notes");

      const data: Note[] = await response.json();
      setNotes(data);
      setError("");
    } catch {
      setError("Unable to connect to the server.");
    } finally {
      setLoading(false);
    }
  };

  
useEffect(() => {
  let cancelled = false;

  const loadInitialNotes = async () => {
    try {
      const response = await fetch(`${API_URL}/notes`);

      if (!response.ok) {
        throw new Error("Unable to fetch notes");
      }

      const data: Note[] = await response.json();

      if (!cancelled) {
        setNotes(data);
        setError("");
      }
    } catch {
      if (!cancelled) {
        setError("Unable to connect to the server.");
      }
    } finally {
      if (!cancelled) {
        setLoading(false);
      }
    }
  };

  void loadInitialNotes();

  return () => {
    cancelled = true;
  };
}, []);


  const addNote = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();

    if (!content.trim()) return;

    setSaving(true);
    setError("");

    try {
      const response = await fetch(`${API_URL}/notes`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ content: content.trim() }),
      });

      if (!response.ok) throw new Error("Unable to save note");

      setContent("");
      await fetchNotes();
    } catch {
      setError("Could not save your note. Please try again.");
    } finally {
      setSaving(false);
    }
  };

  const deleteNote = async (id: number) => {
    try {
      const response = await fetch(`${API_URL}/notes/${id}`, {
        method: "DELETE",
      });

      if (!response.ok) throw new Error("Unable to delete note");

      await fetchNotes();
    } catch {
      setError("Could not delete the note.");
    }
  };

  return (
    <main className="min-h-screen bg-gray-50 px-5 py-16 text-gray-900">
      <div className="mx-auto max-w-2xl">
        <h1 className="text-3xl font-semibold tracking-tight">
          My Notes
        </h1>

        <p className="mt-2 text-sm text-gray-500">
          Keep your thoughts and ideas in one place.
        </p>

        <form onSubmit={addNote} className="mt-10">
          <textarea
            value={content}
            onChange={(e) => setContent(e.target.value)}
            placeholder="Write something..."
            rows={4}
            className="w-full resize-none rounded-lg border border-gray-200 bg-white p-4 text-sm outline-none transition focus:border-gray-400"
          />

          <div className="mt-3 flex justify-end">
            <button
              type="submit"
              disabled={saving || !content.trim()}
              className="rounded-lg bg-gray-900 px-5 py-2.5 text-sm text-white transition hover:bg-gray-700 disabled:cursor-not-allowed disabled:opacity-50"
            >
              {saving ? "Saving..." : "Save note"}
            </button>
          </div>
        </form>

        {error && (
          <p className="mt-5 rounded-lg bg-red-50 p-3 text-sm text-red-600">
            {error}
          </p>
        )}

        <section className="mt-12">
          <h2 className="mb-5 text-lg font-medium">Your notes</h2>

          {loading ? (
            <p className="text-sm text-gray-500">Loading notes...</p>
          ) : notes.length === 0 ? (
            <p className="rounded-lg border border-dashed border-gray-300 p-8 text-center text-sm text-gray-500">
              No notes yet. Add your first note above.
            </p>
          ) : (
            <div className="space-y-3">
              {notes.map((note) => (
                <div
                  key={note.id}
                  className="flex items-start justify-between gap-4 rounded-lg border border-gray-200 bg-white p-4"
                >
                  <p className="whitespace-pre-wrap text-sm leading-6">
                    {note.content}
                  </p>

                  <button
                    onClick={() => deleteNote(note.id)}
                    className="shrink-0 text-xs text-gray-400 hover:text-red-600"
                    aria-label="Delete note"
                  >
                    Delete
                  </button>
                </div>
              ))}
            </div>
          )}
        </section>
      </div>
    </main>
  );
}
