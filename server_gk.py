from fastapi import FastAPI, UploadFile
from pydantic import BaseModel
from fastapi.responses import FileResponse
from audio_separator.separator import Separator
import os
import shutil
import whisper

server = FastAPI()

model = whisper.load_model("base")

class Song:
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

song_list = []
current_id = 0

@server.get("/")
def root():
    return {".WAV storage container"}

@server.post("/uploadfile/")
async def upload_song(file: UploadFile):
    # expects filename like: SongName - ArtistName.wav
    index = file.filename.find('-')
    index2 = file.filename.rfind('.')

    if index == -1 or index2 == -1:
        return {"success": False, "error": "Filename must look like 'Song - Artist.wav'"}

    new_song = Song(
        file.filename[:index-1],
        file.filename[index+2:index2],
        file.filename
    )

    song_dir = new_song.name
    source_wav_path = os.path.join(song_dir, f"{new_song.name} - {new_song.artist}.wav")
    vocals_path = os.path.join(song_dir, f"{new_song.name} - {new_song.artist}_vocals.wav")
    drums_path = os.path.join(song_dir, f"{new_song.name} - {new_song.artist}_drums.wav")
    bass_path = os.path.join(song_dir, f"{new_song.name} - {new_song.artist}_bass.wav")
    guitar_path = os.path.join(song_dir, f"{new_song.name} - {new_song.artist}_guitar.wav")
    lyrics_path = os.path.join(song_dir, f"{new_song.name} - {new_song.artist}_lyrics.txt")

    # create song directory if needed
    os.makedirs(song_dir, exist_ok=True)

    # only add to song_list if not already present
    already_in_list = any(
        s.name == new_song.name and s.artist == new_song.artist
        for s in song_list
    )
    if not already_in_list:
        song_list.append(new_song)
    else:
        # reuse the existing song object so lyric_file stays consistent
        for s in song_list:
            if s.name == new_song.name and s.artist == new_song.artist:
                new_song = s
                break

    # if everything already exists, skip expensive processing
    already_processed = (
        os.path.exists(source_wav_path) and
        os.path.exists(vocals_path) and
        os.path.exists(drums_path) and
        os.path.exists(bass_path) and
        os.path.exists(guitar_path) and
        os.path.exists(lyrics_path)
    )

    if already_processed:
        new_song.lyric_file = lyrics_path
        print("Song already processed, skipping separation and transcription.")
        return {
            "success": True,
            "message": "Song already processed",
            "song_name": new_song.name,
            "artist": new_song.artist
        }

    # save uploaded wav into the song folder
    contents = await file.read()
    with open(source_wav_path, "wb") as f:
        f.write(contents)

    # run separation only if stems are missing
    stems_exist = (
        os.path.exists(vocals_path) and
        os.path.exists(drums_path) and
        os.path.exists(bass_path) and
        os.path.exists(guitar_path)
    )
    if not stems_exist:
        separate_song(new_song)

    # run lyrics only if missing
    if not os.path.exists(lyrics_path):
        extract_lyrics(new_song)

    new_song.lyric_file = lyrics_path
    print(new_song.lyric_file)

    return {
        "success": True,
        "message": "Upload and processing complete",
        "song_name": new_song.name,
        "artist": new_song.artist
    }

@server.get("/requests/{song_title}/{instrument_type}")
async def return_song(song_title: str, instrument_type: str):
    song_dir = song_title

    if not os.path.exists(song_dir):
        return {"success": False, "error": "Song does not exist"}

    files = os.listdir(song_dir)

    for f in files:
        if f.endswith(f"_{instrument_type}.wav"):
            return FileResponse(os.path.join(song_dir, f))

    return {"success": False, "error": "Stem file does not exist"}


@server.get("/requests/{song_title}_lyrics")
def return_lyrics(song_title: str):
    song_dir = song_title

    if not os.path.exists(song_dir):
        return {"success": False, "error": "Song does not exist"}

    files = os.listdir(song_dir)

    for f in files:
        if f.endswith("_lyrics.txt"):
            return FileResponse(os.path.join(song_dir, f))

    return {"success": False, "error": "Lyrics file does not exist"}

@server.get("/song_exists/{song_title}/{artist}")
def song_exists(song_title: str, artist: str):
    source_wav_path = os.path.join(song_title, f"{song_title} - {artist}.wav")
    vocals_path = os.path.join(song_title, f"{song_title} - {artist}_vocals.wav")
    drums_path = os.path.join(song_title, f"{song_title} - {artist}_drums.wav")
    bass_path = os.path.join(song_title, f"{song_title} - {artist}_bass.wav")
    guitar_path = os.path.join(song_title, f"{song_title} - {artist}_guitar.wav")
    lyrics_path = os.path.join(song_title, f"{song_title} - {artist}_lyrics.txt")

    exists = (
        os.path.exists(source_wav_path) and
        os.path.exists(vocals_path) and
        os.path.exists(drums_path) and
        os.path.exists(bass_path) and
        os.path.exists(guitar_path) and
        os.path.exists(lyrics_path)
    )

    return {
        "exists": exists,
        "song_name": song_title,
        "artist": artist
    }


######## HELPER FUNCTIONS

def separate_song(song_obj):
    separator = Separator()
    separator.load_model("htdemucs.yaml")

    output_names = {
        "Vocals": song_obj.name + " - " + song_obj.artist + "_vocals",
        "Drums": song_obj.name + " - " + song_obj.artist + "_drums",
        "Bass": song_obj.name + " - " + song_obj.artist + "_bass",
        "Other": song_obj.name + " - " + song_obj.artist + "_guitar"
    }

    input_wav_path = os.path.join(song_obj.name, f"{song_obj.name} - {song_obj.artist}.wav")
    separator.separate(input_wav_path, output_names)

    stem_names = [
        f"{song_obj.name} - {song_obj.artist}_vocals.wav",
        f"{song_obj.name} - {song_obj.artist}_drums.wav",
        f"{song_obj.name} - {song_obj.artist}_bass.wav",
        f"{song_obj.name} - {song_obj.artist}_guitar.wav",
    ]

    for stem_file in stem_names:
        src = stem_file
        dst = os.path.join(song_obj.name, stem_file)

        if os.path.exists(src):
            if os.path.exists(dst):
                os.remove(dst)
            shutil.move(src, dst)
            print(f"Moved {src} -> {dst}")
        else:
            print(f"Expected stem not found in root: {src}")

def extract_lyrics(song_obj):
    vocals_path = os.path.join(
        song_obj.name,
        f"{song_obj.name} - {song_obj.artist}_vocals.wav"
    )

    result = model.transcribe(vocals_path, fp16=False)

    lyrics_path = os.path.join(
        song_obj.name,
        f"{song_obj.name} - {song_obj.artist}_lyrics.txt"
    )

    with open(lyrics_path, "w") as f:
        for segment in result["segments"]:
            text = segment["text"].strip()
            if text:
                f.write(text + "\n")