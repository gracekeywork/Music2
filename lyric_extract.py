import whisper

# 1. LOAD THE MODEL GLOBALLY (outside the function)
# This way it only happens ONCE when the script starts.
# Use 'medium' or pass the model object into the function.
model_cache = {}

def get_model(modelname):
    if modelname not in model_cache:
        print(f"--- Loading {modelname} model into memory... ---")
        model_cache[modelname] = whisper.load_model(modelname)
    return model_cache[modelname]

def lyric_extract(filename, destination, modelname):
    # Retrieve the pre-loaded model
    model = get_model(modelname)
    
    print(f"--- Transcribing {filename} with {modelname}... ---")
    
    result = model.transcribe(
        audio=filename,
        fp16=False,
        beam_size=5,  #boosts quality
        condition_on_previous_text=False
    )

    # Save to file
    with open(destination, "w", encoding="utf-8") as f:
        for s in result["segments"]:
            f.write(s["text"].strip() + '\n')
