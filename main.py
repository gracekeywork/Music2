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

    # 1. SET ARTIST AND SONG NAME OF FILE (ex. song_name - artist_name.wav)
    index = file.filename.find('-')
    index2 = file.filename.find('.')
    
    # Using strip() to remove accidental trailing/leading spaces
    song_name = file.filename[:index-1].strip()
    artist_name = file.filename[index+2:index2].strip()
    new_song = Song(song_name, artist_name, song_name+' - '+artist_name)

    # ADD NEW SONG TO LIST IF IT DOES NOT EXIST
    for song in song_list:
        if song.name == new_song.name:
            pass
        
    song_list.append(new_song)
    
    # Make directory for the song
    os.makedirs(new_song.name, exist_ok=True)

    # Save the uploaded file locally
    with open(file.filename, "wb") as f:
        contents = await file.read()
        f.write(contents)

    # ==========================================
    # --- AUTOMATED AUDIO PROCESSING PIPELINE ---
    # ==========================================

    # 2. SEPARATE AUDIO STEMS
    # Ensure separate_song outputs standard files like "Song - Artist_(Vocals|Drums).wav"
    separate_song(new_song.filename)
    
    # Predict the name of the extracted vocals file based on your demucs output
    vocals_file = f"{new_song.name} - {new_song.artist}_vocals.wav" # adjust capitalization if needed

    # 3. EXTRACT LYRICS VIA WHISPER (Base, Small, Medium)
    base_file = f"{new_song.name}_base.txt"
    small_file = f"{new_song.name}_small.txt"
    medium_file = f"{new_song.name}_medium.txt"

    lyric_extract(vocals_file, base_file, "base")
    lyric_extract(vocals_file, small_file, "small")
    lyric_extract(vocals_file, medium_file, "medium")

    # 4. COMPILE LYRICS
    # lyric_compile uses the songname prefix to locate the 3 text files
    lyric_compile(new_song.name)
    finalized_lyrics = f"{new_song.name}_lyrics_finalized.txt"

    # 5. SYNC LYRICS WITH FREQUENCY DATA
    vocal_data = Frequency_data(vocals_file)
    fill_data(vocal_data)
    estimate_chunks(vocal_data)
    lyric_sync(vocal_data, finalized_lyrics)

    # 6. MAKE .PCM FILES FOR EACH INSTRUMENT
    convert_to_pcm(f"{new_song.filename}_vocals.wav", "vocals")
    convert_to_pcm(f"{new_song.filename}_drums.wav", "drums")
    convert_to_pcm(f"{new_song.filename}_bass.wav", "bass")
    convert_to_pcm(f"{new_song.filename}_guitar.wav", "guitar")

    # ==========================================
    # --- FILE CLEANUP AND ORGANIZATION ---
    # ==========================================

    # Move all intermediate and final files into the song's directory
    files_to_move = [
        new_song.filename,
        vocals_file,
        f"{new_song.name} - {new_song.artist}_drums.wav",
        f"{new_song.name} - {new_song.artist}_bass.wav",
        f"{new_song.name} - {new_song.artist}_guitar.wav",
        base_file,
        small_file,
        medium_file,
        finalized_lyrics,
        "lyrics_with_timestamps_"+new_song.name+".txt"
    ]

    for f_name in files_to_move:
        if os.path.exists(f_name):
            # If moving the hardcoded timestamp file, rename it to match the song
            if f_name == "lyrics_with_timestamps_.txt":
                destination = os.path.join(new_song.name, f"{new_song.name}_synced_lyrics.txt")
                shutil.move(f_name, destination)
                new_song.lyric_file = destination
            else:
                shutil.move(f_name, os.path.join(new_song.name, f_name))

    print(f"Pipeline complete. Synced lyrics saved to: {new_song.lyric_file}")
    return True

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
