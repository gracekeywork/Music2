from audio_separator.separator import Separator

def separate_song(filename):
    separator = Separator()
    separator.load_model('htdemucs.yaml')
    output_names = {
        "Vocals": filename + "_vocals",
        "Drums": filename + "_drums",
        "Bass": filename + "_bass",
        "Other": filename + "_guitar"
    }
    separator.separate(filename+".wav", output_names)
