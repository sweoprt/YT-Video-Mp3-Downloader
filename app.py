import json
import shutil
import subprocess
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk


RESOLUTION_OPTIONS = ["Best", "2160p", "1440p", "1080p", "720p", "480p", "360p", "240p", "144p"]
DEFAULT_OUTPUT_DIR = str(Path.home() / "Downloads")


class YouTubeDownloaderApp:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.root.title("YouTube Downloader")
        self.root.geometry("760x620")
        self.root.minsize(700, 560)

        self.available_resolutions = RESOLUTION_OPTIONS.copy()

        self.url_var = tk.StringVar()
        self.output_var = tk.StringVar(value=DEFAULT_OUTPUT_DIR)
        self.format_var = tk.StringVar(value="MP4")
        self.resolution_var = tk.StringVar(value="Best")
        self.status_var = tk.StringVar(value="Ready")

        self._build_ui()
        self._refresh_resolution_state()

    def _build_ui(self) -> None:
        container = ttk.Frame(self.root, padding=18)
        container.pack(fill="both", expand=True)
        container.columnconfigure(1, weight=1)

        title = ttk.Label(container, text="YouTube Video Downloader", font=("Segoe UI", 18, "bold"))
        title.grid(row=0, column=0, columnspan=3, sticky="w", pady=(0, 8))

        subtitle = ttk.Label(
            container,
            text="Download a YouTube video as MP4 or extract audio as MP3. Use only for content you have rights to save.",
            wraplength=680,
        )
        subtitle.grid(row=1, column=0, columnspan=3, sticky="w", pady=(0, 18))

        ttk.Label(container, text="Video URL").grid(row=2, column=0, sticky="w", pady=6)
        ttk.Entry(container, textvariable=self.url_var).grid(row=2, column=1, columnspan=2, sticky="ew", pady=6)

        ttk.Label(container, text="Save To").grid(row=3, column=0, sticky="w", pady=6)
        ttk.Entry(container, textvariable=self.output_var).grid(row=3, column=1, sticky="ew", pady=6)
        ttk.Button(container, text="Browse", command=self._choose_output_dir).grid(row=3, column=2, sticky="ew", padx=(10, 0), pady=6)

        ttk.Label(container, text="Format").grid(row=4, column=0, sticky="w", pady=6)
        self.format_box = ttk.Combobox(container, textvariable=self.format_var, values=["MP4", "MP3"], state="readonly")
        self.format_box.grid(row=4, column=1, sticky="w", pady=6)
        self.format_box.bind("<<ComboboxSelected>>", self._on_format_change)

        ttk.Label(container, text="Resolution").grid(row=5, column=0, sticky="w", pady=6)
        self.resolution_box = ttk.Combobox(
            container,
            textvariable=self.resolution_var,
            values=self.available_resolutions,
            state="readonly",
        )
        self.resolution_box.grid(row=5, column=1, sticky="w", pady=6)

        button_row = ttk.Frame(container)
        button_row.grid(row=6, column=0, columnspan=3, sticky="ew", pady=(16, 10))
        button_row.columnconfigure(0, weight=1)
        button_row.columnconfigure(1, weight=1)
        button_row.columnconfigure(2, weight=1)

        self.fetch_button = ttk.Button(button_row, text="Load Resolutions", command=self._load_resolutions)
        self.fetch_button.grid(row=0, column=0, sticky="ew", padx=(0, 8))

        self.download_button = ttk.Button(button_row, text="Download", command=self._start_download)
        self.download_button.grid(row=0, column=1, sticky="ew", padx=4)

        self.clear_button = ttk.Button(button_row, text="Clear Log", command=self._clear_log)
        self.clear_button.grid(row=0, column=2, sticky="ew", padx=(8, 0))

        ttk.Label(container, text="Status").grid(row=7, column=0, sticky="w", pady=(6, 2))
        ttk.Label(container, textvariable=self.status_var, foreground="#0a5").grid(row=7, column=1, columnspan=2, sticky="w", pady=(6, 2))

        ttk.Label(container, text="Progress / Log").grid(row=8, column=0, sticky="w", pady=(14, 6))
        self.log_text = tk.Text(container, height=18, wrap="word", font=("Consolas", 10))
        self.log_text.grid(row=9, column=0, columnspan=3, sticky="nsew")
        container.rowconfigure(9, weight=1)

        scrollbar = ttk.Scrollbar(container, orient="vertical", command=self.log_text.yview)
        scrollbar.grid(row=9, column=3, sticky="ns")
        self.log_text.configure(yscrollcommand=scrollbar.set)
        self.log_text.insert("end", "App ready.\n")
        self.log_text.configure(state="disabled")

    def _choose_output_dir(self) -> None:
        chosen = filedialog.askdirectory(initialdir=self.output_var.get() or DEFAULT_OUTPUT_DIR)
        if chosen:
            self.output_var.set(chosen)

    def _on_format_change(self, _event=None) -> None:
        self._refresh_resolution_state()

    def _refresh_resolution_state(self) -> None:
        if self.format_var.get() == "MP3":
            self.resolution_var.set("Best")
            self.resolution_box.configure(state="disabled")
        else:
            self.resolution_box.configure(state="readonly")
            if self.resolution_var.get() not in self.available_resolutions:
                self.resolution_var.set("Best")

    def _load_resolutions(self) -> None:
        url = self.url_var.get().strip()
        if not url:
            messagebox.showerror("Missing URL", "Paste a YouTube URL first.")
            return

        yt_dlp_path = self._find_command("yt-dlp")
        if not yt_dlp_path:
            messagebox.showerror("Missing yt-dlp", "yt-dlp was not found. Read the README for setup steps.")
            return

        self._set_busy(True, "Loading available resolutions...")
        self._log("Fetching video information...")

        def worker() -> None:
            try:
                command = [yt_dlp_path, "--dump-single-json", "--no-playlist", url]
                result = subprocess.run(command, capture_output=True, text=True, check=True)
                info = json.loads(result.stdout)
                resolutions = self._extract_resolutions(info)
                self.available_resolutions = ["Best"] + resolutions if resolutions else RESOLUTION_OPTIONS.copy()
                self.root.after(0, self._update_resolutions)
                self.root.after(0, lambda: self._log("Resolution list updated."))
                self.root.after(0, lambda: self.status_var.set("Resolution list loaded"))
            except subprocess.CalledProcessError as exc:
                error_text = exc.stderr.strip() or exc.stdout.strip() or str(exc)
                self.root.after(0, lambda: messagebox.showerror("Failed", error_text))
                self.root.after(0, lambda: self._log(f"Could not load formats: {error_text}"))
                self.root.after(0, lambda: self.status_var.set("Failed to load resolutions"))
            except json.JSONDecodeError:
                self.root.after(0, lambda: messagebox.showerror("Failed", "yt-dlp returned unreadable video metadata."))
                self.root.after(0, lambda: self.status_var.set("Failed to parse metadata"))
            finally:
                self.root.after(0, lambda: self._set_busy(False))

        threading.Thread(target=worker, daemon=True).start()

    def _update_resolutions(self) -> None:
        self.resolution_box.configure(values=self.available_resolutions)
        if self.resolution_var.get() not in self.available_resolutions:
            self.resolution_var.set("Best")
        self._refresh_resolution_state()

    def _extract_resolutions(self, info: dict) -> list[str]:
        heights: set[int] = set()
        for fmt in info.get("formats", []):
            if fmt.get("vcodec") == "none":
                continue
            height = fmt.get("height")
            if isinstance(height, int) and height > 0:
                heights.add(height)

        return [f"{height}p" for height in sorted(heights, reverse=True)]

    def _start_download(self) -> None:
        url = self.url_var.get().strip()
        output_dir = self.output_var.get().strip()
        selected_format = self.format_var.get().strip()
        resolution = self.resolution_var.get().strip()

        if not url:
            messagebox.showerror("Missing URL", "Paste a YouTube URL first.")
            return

        if not output_dir:
            messagebox.showerror("Missing Folder", "Choose where the file should be saved.")
            return

        if not Path(output_dir).exists():
            messagebox.showerror("Missing Folder", "The selected save folder does not exist.")
            return

        yt_dlp_path = self._find_command("yt-dlp")
        if not yt_dlp_path:
            messagebox.showerror("Missing yt-dlp", "yt-dlp was not found. Read the README for setup steps.")
            return

        if not self._find_command("ffmpeg"):
            messagebox.showerror("Missing ffmpeg", "ffmpeg is required for MP3 conversion and most MP4 merges. Read the README for setup steps.")
            return

        self._set_busy(True, f"Downloading {selected_format}...")
        self._log(f"Starting download: {url}")
        self._log(f"Format: {selected_format} | Resolution: {resolution}")

        threading.Thread(
            target=self._run_download,
            args=(yt_dlp_path, url, output_dir, selected_format, resolution),
            daemon=True,
        ).start()

    def _run_download(self, yt_dlp_path: str, url: str, output_dir: str, selected_format: str, resolution: str) -> None:
        command = self._build_download_command(yt_dlp_path, url, output_dir, selected_format, resolution)

        try:
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )
        except OSError as exc:
            self.root.after(0, lambda: messagebox.showerror("Failed", str(exc)))
            self.root.after(0, lambda: self._set_busy(False, "Ready"))
            return

        assert process.stdout is not None
        for line in process.stdout:
            clean_line = line.strip()
            if clean_line:
                self.root.after(0, lambda msg=clean_line: self._log(msg))
                if "[download]" in clean_line:
                    self.root.after(0, lambda msg=clean_line: self.status_var.set(msg[:120]))

        return_code = process.wait()
        if return_code == 0:
            self.root.after(0, lambda: self._log("Download completed successfully."))
            self.root.after(0, lambda: self._set_busy(False, "Download finished"))
            self.root.after(0, lambda: messagebox.showinfo("Success", "The download finished successfully."))
        else:
            self.root.after(0, lambda: self._log(f"Download failed with exit code {return_code}."))
            self.root.after(0, lambda: self._set_busy(False, "Download failed"))
            self.root.after(0, lambda: messagebox.showerror("Failed", f"Download failed with exit code {return_code}."))

    def _build_download_command(
        self,
        yt_dlp_path: str,
        url: str,
        output_dir: str,
        selected_format: str,
        resolution: str,
    ) -> list[str]:
        output_template = str(Path(output_dir) / "%(title)s.%(ext)s")
        command = [yt_dlp_path, "--newline", "--no-playlist", "-o", output_template]

        if selected_format == "MP3":
            command.extend(["-x", "--audio-format", "mp3", "--audio-quality", "0"])
        else:
            if resolution == "Best":
                format_selector = "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/best"
            else:
                height = resolution.replace("p", "")
                format_selector = (
                    f"bv*[ext=mp4][height<={height}]+ba[ext=m4a]/"
                    f"b[ext=mp4][height<={height}]/best[height<={height}]"
                )
            command.extend(["-f", format_selector, "--merge-output-format", "mp4"])

        command.append(url)
        return command

    def _find_command(self, command_name: str) -> str | None:
        resolved = shutil.which(command_name)
        if resolved:
            return resolved

        local_candidates = [
            Path.cwd() / f"{command_name}.exe",
            Path.cwd() / "bin" / f"{command_name}.exe",
            Path(__file__).resolve().parent / f"{command_name}.exe",
            Path(__file__).resolve().parent / "bin" / f"{command_name}.exe",
        ]
        for candidate in local_candidates:
            if candidate.exists():
                return str(candidate)
        return None

    def _set_busy(self, is_busy: bool, status: str | None = None) -> None:
        state = "disabled" if is_busy else "normal"
        self.fetch_button.configure(state=state)
        self.download_button.configure(state=state)
        self.clear_button.configure(state=state)
        self.format_box.configure(state="disabled" if is_busy else "readonly")
        self.resolution_box.configure(state="disabled" if is_busy or self.format_var.get() == "MP3" else "readonly")
        if status is not None:
            self.status_var.set(status)

    def _log(self, message: str) -> None:
        self.log_text.configure(state="normal")
        self.log_text.insert("end", f"{message}\n")
        self.log_text.see("end")
        self.log_text.configure(state="disabled")

    def _clear_log(self) -> None:
        self.log_text.configure(state="normal")
        self.log_text.delete("1.0", "end")
        self.log_text.insert("end", "Log cleared.\n")
        self.log_text.configure(state="disabled")

def main() -> None:
    root = tk.Tk()
    style = ttk.Style(root)
    if "vista" in style.theme_names():
        style.theme_use("vista")
    app = YouTubeDownloaderApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
