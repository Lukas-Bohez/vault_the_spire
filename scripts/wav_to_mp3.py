# Convert WAV to MP3
# Requires: pydub, ffmpeg
from pydub import AudioSegment
import os

# Define file paths
files = [
    ("assets/sounds/click.wav", "assets/sounds/click.mp3"),
    ("assets/sounds/notification.wav", "assets/sounds/notification.mp3")
]

for wav_path, mp3_path in files:
    sound = AudioSegment.from_wav(wav_path)
    sound.export(mp3_path, format="mp3")
    print(f"Converted {wav_path} -> {mp3_path}")

# Optionally, delete the original .wav files
delete = input("Delete original .wav files? (y/n): ").strip().lower()
if delete == 'y':
    for wav_path, _ in files:
        os.remove(wav_path)
        print(f"Deleted {wav_path}")
else:
    print("Original .wav files kept.")
