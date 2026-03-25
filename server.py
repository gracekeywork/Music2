from fastapi import FastAPI, UploadFile
from pydantic import BaseModel
from fastapi.responses import FileResponse
from audio_separator.separator import Separator
import os
import shutil
import whisper

server = FastAPI()

model = whisper.load_model("base")

class Song():
    def __init__(self, name, artist, filename):
        self.name = name
        self.artist = artist
        self.filename = filename
        self.lyric_file = ""

class Song_request(BaseModel):
    name : str
    artist : str | None = None
    index : int | None = None
    file : str | None = None

#CREATE SONG OBJECTS HERE IF THEY ARE ALREADY STORED LOCALLY
#server won't return a song if it isn't uploaded first; this bypasses the need to "upload" when testing
song_list = [Song("Rooster", "Alice in Chains", "Rooster - Alice in Chains.wav")]
current_id = 0

@server.get("/") #decorator: links the below function to the path "/" and operation get
def root():
    return {".WAV storage container"}

@server.post("/uploadfile/")
async def upload_song(file: UploadFile):

    #SET ARTIST AND SONG NAME OF FILE (ex. song_name - artist_name)
    index = file.filename.find('-')
    index2 = file.filename.find('.')
    new_song = Song(file.filename[:index-1], file.filename[index+2:index2], file.filename)

    #ADD NEW SONG TO LIST IF DNE ALREADY
    for song in song_list:
        if song.name == new_song.name:
            return "Song already exists"
        
    #IF LOOP REACHES HERE, SONG DOES NOT YET EXIST
    #APPEND TO LIST, MAKE DIRECTORY, AND SAVE TO DIRECTORY
    song_list.append(new_song)
    os.mkdir(new_song.name)

    with open(file.filename, "wb") as f:
        contents = await file.read()
        f.write(contents)

    #run song separation
    separate_song(new_song)

    #run lyric extraction
    extract_lyrics(new_song)

    #before returning true, move all files into its 'Song name' directory
    shutil.move(new_song.name+" - "+new_song.artist+".wav", new_song.name)
    shutil.move(new_song.name+" - "+new_song.artist+"_vocals.wav", new_song.name)
    shutil.move(new_song.name+" - "+new_song.artist+"_drums.wav", new_song.name)
    shutil.move(new_song.name+" - "+new_song.artist+"_bass.wav", new_song.name)
    shutil.move(new_song.name+" - "+new_song.artist+"_guitar.wav", new_song.name)
    shutil.move(new_song.name+" - "+new_song.artist+"_lyrics.txt", new_song.name)

    #SAVE LYRIC FILEPATH
    new_song.lyric_file = new_song.name+"/"+new_song.name+" - "+new_song.artist+"_lyrics.txt"
    print(new_song.lyric_file)

    return True

@server.get("/requests/{song_title}/{instrument_type}")
async def return_song(song_title: str, instrument_type: str):
    return_file = ''
    #PARSE SONG LIST FOR MATCHING TITLE
    for song in song_list:
        if song.name == song_title:
            #RETURN PROPER INSTRUMENT STEM (song_name/song_name - artist_name.instrument.wav)
            return_file = song.name+"/"+song.name+" - "+song.artist+"_"+instrument_type+".wav"
            return FileResponse(return_file)
    if return_file == '':
        return "File DNE"

@server.get("/requests/{song_title}_lyrics")
def return_lyrics(song_title: str):
    for song in song_list:
        if song.name == song_title:
            return FileResponse(song.lyric_file)
        




########HELPER FUNCTIONS

def separate_song(song_obj):
    separator = Separator()
    separator.load_model('htdemucs.yaml')
    #names the output files in the format song name - artist_instrument.wav
    output_names = {
        "Vocals": song_obj.name+" - "+song_obj.artist+"_vocals",
        "Drums": song_obj.name+" - "+song_obj.artist+"_drums",
        "Bass": song_obj.name+" - "+song_obj.artist+"_bass",
        "Other": song_obj.name+" - "+song_obj.artist+"_guitar"
    }

    separator.output_dir = song_obj.name
    print(separator.output_dir)
    separator.separate(song_obj.filename, output_names)

def extract_lyrics(song_obj):
    result = model.transcribe(song_obj.name+" - "+song_obj.artist+"_vocals.wav", fp16=False) #disable 16 bit floating point so it uses 32 on cpu
    lyric_text = ''
    for c in result["text"]:
        if c == '.':
            lyric_text += '\n'
        else:
            lyric_text += c

    #create lyric file and write to it
    with open(song_obj.name+" - "+song_obj.artist+"_lyrics.txt", "w") as f:
        f.write(lyric_text)

#uvicorn server:server --reload <-- private launch
#uvicorn server:server --host 10.5.2.150 --port 8000 --reload
