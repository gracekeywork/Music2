from fastapi import FastAPI, UploadFile
from pydantic import BaseModel
from fastapi.responses import FileResponse
from audio_separator.separator import Separator
import os

server = FastAPI()

class Song():
    def __init__(self, name, artist, filename):
        self.name = name
        self.artist = artist
        self.filename = filename
        self.lyrics = ""

class Song_request(BaseModel):
    name : str
    artist : str | None = None
    index : int | None = None
    file : str | None = None

song_list = []
current_id = 0

@server.get("/") #decorator: links the below function to the path "/" and operation get
def root():
    return {".WAV storage container"}

@server.post("/uploadfile/")
async def upload_song(file: UploadFile):

    #below assumes a uniform naming convention for wav files (ex. song_name - artist_name)
    index = file.filename.find('-')
    index2 = file.filename.find('.')
    new_song = Song(file.filename[:index-1], file.filename[index+2:index2], file.filename)

    #add new song to list
    song_list.append(new_song)

    #create directory SHOULD PROBABLY ADD FILEEXISTSERROR EXCEPTION HERE
    os.mkdir(new_song.name)

    #save the .wav file
    with open(file.filename, "wb") as f:
        contents = await file.read()
        f.write(contents)

        #run song separation before returning true
        separate_song(new_song)

        return True

@server.get("/requests/{song_title}/{instrument_type}")
async def return_song(song_title: str, instrument_type: str):
    return_file = ''
    for item in song_list:
        if item.name == song_title:
            song_file = item.filename
            index = song_file.find('.')
            return_file = song_file[:index] + instrument_type +'.wav'
            return FileResponse(return_file)
    if return_file == '':
        return "File DNE"

@server.get("requests/{song_title}_lyrics")
def return_lyrics(song_title: str):
    return song_title.lyrics

def separate_song(song_obj):
    separator = Separator()
    separator.load_model('htdemucs.yaml')
    #names the output files in the format song name - artist_instrument.wav
    output_names = {
        "Vocals": song_obj.name+" - "+song_obj.artist+"_vocals.wav",
        "Drums": song_obj.name+" - "+song_obj.artist+"_drums.wav",
        "Bass": song_obj.name+" - "+song_obj.artist+"_bass.wav",
        "Guitar": song_obj.name+" - "+song_obj.artist+"_guitar.wav"
    }

    separator.output_dir = song_obj.name
    separator.separate(song_obj.filename, output_names)

#uvicorn server:server --reload <-- private launch
#uvicorn server:server --host 10.5.22.60 --port 8000 --reload
