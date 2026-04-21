from fastapi import FastAPI, UploadFile
from pydantic import BaseModel
from fastapi.responses import FileResponse
import os
import shutil

# --- IMPORTS FROM YOUR CUSTOM MODULES ---
from audio_split import separate_song
from lyric_extract import lyric_extract
from lyric_compilation import lyric_compile
from frequency_control import Frequency_data, fill_data, estimate_chunks, lyric_sync
from downsampling import convert_to_pcm

main = FastAPI()

class Song():
    def __init__(self, name, artist, filename):
        self.name = name
        self.artist = artist
        self.filename = filename
        self.lyric_file = ""

class Song_request(BaseModel):
    name: str
    artist: str | None = None
    index: int | None = None
    file: str | None = None

# Bypass the need to "upload" when testing
song_list = [Song("Rooster", "Alice in Chains", "Rooster - Alice in Chains.wav")]
current_id = 0

@main.get("/")
def root():
    return {".WAV storage container"}


@main.post("/uploadfile/")
async def upload_song(file: UploadFile):

    # 1. PARSE SONG NAME / ARTIST
    index = file.filename.find('-')
    index2 = file.filename.rfind('.')

    song_name = file.filename[:index-1].strip()
    artist_name = file.filename[index+2:index2].strip()

    #new_song = Song(song_name, artist_name, song_name + ' - ' + artist_name )
    new_song = Song(song_name, artist_name, song_name+' - '+artist_name)

    song_dir = new_song.name
    synced_lyrics_path = os.path.join(song_dir, f"{new_song.name}_synced_lyrics.txt")
    vocals_path = os.path.join(song_dir, f"{new_song.name} - {new_song.artist}_vocals.wav")
    drums_path = os.path.join(song_dir, f"{new_song.name} - {new_song.artist}_drums.wav")
    bass_path = os.path.join(song_dir, f"{new_song.name} - {new_song.artist}_bass.wav")
    guitar_path = os.path.join(song_dir, f"{new_song.name} - {new_song.artist}_guitar.wav")

    already_processed = (
        os.path.exists(song_dir) and
        os.path.exists(synced_lyrics_path) and
        os.path.exists(vocals_path) and
        os.path.exists(drums_path) and
        os.path.exists(bass_path) and
        os.path.exists(guitar_path)
    )

    if already_processed:
        new_song.lyric_file = synced_lyrics_path
        if not any(s.name == new_song.name for s in song_list):
            song_list.append(new_song)
        return {
            "status": "already_exists",
            "message": f"{new_song.name} already processed. Reusing existing files."
        }

    # otherwise this is a fresh rebuild
    song_list.append(new_song)
    target_song = new_song

    # 5. MAKE DIRECTORY
    os.makedirs(target_song.name, exist_ok=True)

    # 6. SAVE UPLOADED FILE LOCALLY ONLY IF WE NEED TO PROCESS
    with open(file.filename, "wb") as f:
        contents = await file.read()
        f.write(contents)

    # ==========================================
    # --- AUTOMATED AUDIO PROCESSING PIPELINE ---
    # ==========================================

    separate_song(target_song.filename)

    vocals_file = f"{target_song.name} - {target_song.artist}_vocals.wav"

    base_file = f"{target_song.name}_base.txt"
    small_file = f"{target_song.name}_small.txt"
    medium_file = f"{target_song.name}_medium.txt"

    lyric_extract(vocals_file, base_file, "base")
    lyric_extract(vocals_file, small_file, "small")
    lyric_extract(vocals_file, medium_file, "medium")

    lyric_compile(target_song.name)
    finalized_lyrics = f"{target_song.name}_lyrics_finalized.txt"

    vocal_data = Frequency_data(vocals_file)
    fill_data(vocal_data)
    estimate_chunks(vocal_data)
    timestamp_file = lyric_sync(vocal_data, finalized_lyrics)

    convert_to_pcm(f"{target_song.name} - {target_song.artist}_vocals.wav", "vocals")
    convert_to_pcm(f"{target_song.name} - {target_song.artist}_drums.wav", "drums")
    convert_to_pcm(f"{target_song.name} - {target_song.artist}_bass.wav", "bass")
    convert_to_pcm(f"{target_song.name} - {target_song.artist}_guitar.wav", "guitar")

    files_to_move = [
        target_song.filename,
        vocals_file,
        f"{target_song.name} - {target_song.artist}_drums.wav",
        f"{target_song.name} - {target_song.artist}_bass.wav",
        f"{target_song.name} - {target_song.artist}_guitar.wav",
        base_file,
        small_file,
        medium_file,
        finalized_lyrics
    ]

    for f_name in files_to_move:
        if os.path.exists(f_name):
            shutil.move(f_name, os.path.join(target_song.name, os.path.basename(f_name)))

    if os.path.exists(timestamp_file):
        destination = os.path.join(target_song.name, f"{target_song.name}_synced_lyrics.txt")
        shutil.move(timestamp_file, destination)
        target_song.lyric_file = destination
    else:
        print(f"Timestamp file missing: {timestamp_file}")

    print(f"Pipeline complete. Synced lyrics saved to: {target_song.lyric_file}")

    return {
        "status": "processed",
        "message": f"{target_song.name} uploaded and processed successfully."
    }

@main.get("/requests/{song_title}/{instrument_type}")
async def return_song(song_title: str, instrument_type: str):
    return_file = ''
    for song in song_list:
        if song.name == song_title:
            # Capitalize instrument type to match file naming conventions if necessary
            return_file = f"{song.name}/{song.name} - {song.artist}_{instrument_type}.wav"
            if os.path.exists(return_file):
                return FileResponse(return_file)
    
    return "File DNE"

@main.get("/requests/{song_title}_lyrics")
def return_lyrics(song_title: str):
    for song in song_list:
        if song.name == song_title:
            if os.path.exists(song.lyric_file):
                return FileResponse(song.lyric_file)
    return "Lyrics DNE"

#uvicorn main:main --reload <-- private launch
#uvicorn main:main --host 10.5.2.150 --port 8000 --reload