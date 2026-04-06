import matplotlib.pyplot as plt
import numpy as np
import scipy.io.wavfile as wavfile
from scipy.fftpack import fft, fftfreq

class Frequency_data():
    def __init__(self, filepath):
        self.filepath = filepath
        self.sample_rate = 0
        self.raw_data = []
        self.runtime = 0
        self.x_axis = []
        self.y_axis = []
        self.max_amp = 0
        self.avg_amp = 0
        self.chunk_list = []

def fill_data(data_object):

    #GATHER SAMPLE RATE AND AUDIO DATA
    sample_rate, data = wavfile.read(data_object.filepath)
    
    #ASSIGN TO PASSED OBJECT
    data_object.sample_rate = sample_rate
    data_object.raw_data = data
    data_object.runtime = len(data) / sample_rate

    #CONVERT FROM STEREO TO MONO
    data = np.mean(data, axis=1, dtype=data.dtype)

    #COMPUTE AXES (FOR TIME DOMAIN)
    x_axis = np.arange(0, len(data)/sample_rate, 1/sample_rate)
    y_axis = np.abs(data)

    #COMPUTE MAX AMPLITUDE FOR NORMALIZATION
    max_amp = compute_max_amp(y_axis)
    y_axis = y_axis / max_amp

    #ASSIGN TO PASSED OBJECT
    data_object.x_axis = x_axis
    data_object.y_axis = y_axis

def compute_max_amp(y_axis):
    #COMPUTE MAX AMPLITUDE
    max_amp = 0
    for sample in y_axis:
        if sample > max_amp:
            max_amp = sample

    return max_amp

def compute_avg_amp(y_axis):
    #FUNCTION ASSUMES SIGNAL IS ALREADY NORMALIZED
    avg_amp = 0
    exclusions = 0
    for sample in y_axis:
        #exclude silences:
        if sample < 0.01:
            exclusions += 1
        else:
            avg_amp += float(sample)
    #divide by number of samples minus number of ignored samples
    avg_amp = avg_amp / (len(y_axis) - exclusions)

    return avg_amp

def plot_wav_data(data_object, start_sample=0, end_sample=None):

    #if no end time is specified, default to the full runtime of the song
    if end_sample is None:
        end_sample = data_object.runtime*data_object.sample_rate
    
    #CREATE SNIPPET BASED ON START AND END TIMES
    snippet = data_object.raw_data[int(start_sample):int(end_sample)]
    #CONVERT TO MONO
    snippet = np.mean(snippet, axis=1, dtype=snippet.dtype)

    #RECOMPUTE X AND Y AXES
    x_axis = np.arange(start_sample/data_object.sample_rate, end_sample/data_object.sample_rate, 1/data_object.sample_rate)
    y_axis = np.abs(snippet)
    #calculate fourier transform and corresponding frequency x-axis
    fourier = fft(snippet)
    freqs = fftfreq(len(snippet), d=1/data_object.sample_rate)

    #ensure x and y axes are same length
    min_len = min(len(x_axis), len(y_axis))
    x_axis = x_axis[:min_len]
    y_axis = y_axis[:min_len]

    #compute average amplitude
    avg_amp = compute_avg_amp(y_axis)

    #PLOT TIME DOMAIN
    plt.subplot(3, 1, 1)
    plt.xlabel("Time (s)")
    plt.ylabel("Amplitude")
    plt.plot(x_axis, y_axis, '-')
    #plt.axhline(max_amp/2.3, color='green')
    plt.axhline(avg_amp, color='red')
    
    #PLOT ORIGINAL FREQUENCY DOMAIN
    #set the maximum frequency shown on graph
    max_freq = 1000 ##~=22.05 kHz would be nyquist theorem val
    end = int(len(freqs) // (44100//max_freq))
    #half sampling frequency divided by number of samples
    x_axis = freqs[:end]
    y_axis = np.abs(fourier[:end])
    plt.subplot(3, 1, 2)
    plt.xlabel("Frequency (Hz)")
    plt.ylabel("Amplitude (dB)")
    plt.plot(x_axis, y_axis, '-')

    transformed_snippet = np.empty((len(snippet)))
    current_entry = 0

    for i, sample in enumerate(snippet):
        if i%100 == 0:
            current_entry = snippet[i]
        transformed_snippet[i] = current_entry

    #PSOLA ALGORITHM! <- possibility?
    #CALCULATE FUNADMENTAL FREQUENCY, PERIOD, & SAMPLES PER PERIOD

    #DECIMATION FILTER
    #LOW PASS FILTER
    #EQUALIZER

    #fourier transform process
    fourier = fft(transformed_snippet)
    
    x_axis = freqs[:end]
    y_axis = np.abs(fourier[:end])

    plt.subplot(3, 1, 3)
    plt.xlabel("Frequency (Hz)")
    plt.ylabel("Amplitude (dB)")
    plt.plot(x_axis, y_axis, '-')
    plt.show()

def estimate_chunks(y_axis):

    #FIND AVERAGE AND MAX AMPLITUDES (EXLUDING SILENCES)
    avg_amp = 0
    max_amp = 0
    exclusions = 0
    for sample in y_axis:
        #EXCLUDE SAMPLES BELOW A SILENCE THRESHOLD
        if sample <= 100:
            exclusions += 1
        else:
            #FORCE TO INTEGER SO NO OVERFLOW
            avg_amp += int(sample)
        if sample > max_amp:
            max_amp = sample
    avg_amp /= (len(y_axis) - exclusions)

    #COMPUTE ESTIMATED BLOCKS
    
    #FSM:
    #0 - CHECKING FOR START OF CHUNK
    #1 - CHECKING IF THIS IS TRULY A CHUNK OR JUST A RANDOM FREQUENCY SPIKE
    #2 - IF CHUNK_CHECK IS TRUE, SEARCH FOR END OF CHUNK
    #3 - STORE CHUNK WITH PROPER TIMESTAMP

    state = 0
    start = 0
    silence_start = 0
    chunk_list = []
    for i, sample in enumerate(y_axis):
        if state == 0:
            #IF THE START OF A CHUNK IS DETECTED
            if sample > avg_amp:
                start = i
                state = 1
        #CHECK FOR SILENCE THAT EQUALS OR EXCEEDS 0.5 SECONDS
        elif state == 1:
            if sample < avg_amp:
                silence_start = i
                state = 2
        elif state == 2:
            #if silence has persisted for a second
            if i - silence_start >= 44100:
                state = 3
            #else if sample detects an amplitude spike, go back a state and set silence_start
            elif sample >= avg_amp:
                state = 1
        elif state == 3:
            #IF THE CHUNK IS LESS THAN 0.5 SECONDS TRASH IT
            if silence_start - start < 44100/2:
                state = 0
            else:
                #ADD NEW CHUNK TO LIST AND RESET TO STATE 0
                #APPEND AS SAMPLE #S FOR FUTURE USE
                #SET END OF THE CHUNK AS SILENCE START
                chunk_list.append([start, silence_start])
                state = 0
                start = 0
        else:
            print("FSM has escaped its states")

    return chunk_list

def estimate_words_per_chunk(data_object):
    
    words_per_chunk_list = []

    for chunk in data_object.chunk_list:

        y_axis = data_object.y_axis[chunk[0]:chunk[1]]

        #FIND AVERAGE AND MAX AMPLITUDES (EXLUDING SILENCES)
        avg_amp = 0
        max_amp = 0
        exclusions = 0
        for sample in y_axis:
            #EXCLUDE SAMPLES BELOW A SILENCE THRESHOLD
            if sample <= 100:
                exclusions += 1
            else:
                #FORCE TO INTEGER SO NO OVERFLOW
                avg_amp += int(sample)
            if sample > max_amp:
                max_amp = sample
        avg_amp /= (len(y_axis) - exclusions)

        #COMPUTE ESTIMATED BLOCKS
        
        #FSM:
        #0 - CHECKING FOR START OF CHUNK
        #1 - CHECKING IF THIS IS TRULY A CHUNK OR JUST A RANDOM FREQUENCY SPIKE
        #2 - IF CHUNK_CHECK IS TRUE, SEARCH FOR END OF CHUNK
        #3 - STORE CHUNK WITH PROPER TIMESTAMP
        
        start = 0
        state = 0
        words_in_chunk = 0
        for i, sample in enumerate(y_axis):
            if state == 0:
                #IF THE START OF A CHUNK IS DETECTED
                if sample > max_amp/2.3:
                    #GO TO NEXT STATE TO FIND SHORT SILENCE
                    start = i
                    state = 1
            elif state == 1:
                #SILENCE = BELOW MAX_AMP/2.3 FOR 0.1 SECOND
                if sample < max_amp/2.3:
                    silence_start = i
                    state = 2
            elif state == 2:
                if i - silence_start >= 44100/10:
                    state = 3
                elif sample >= max_amp/2.3:
                    state = 1
            elif state == 3:
                #SCRAP IF WORD IS LESS THAN 0.2 SECONDS
                if silence_start - i < 44100/5:
                    state = 0
                #ADD NEW CHUNK TO LIST AND RESET TO STATE 0
                #APPEND AS SAMPLE #S FOR FUTURE USE
                words_in_chunk += 1
                state = 0
            else:
                print("FSM has escaped its states")

        #account for the fact that the tail end word will NOT be detected
        words_in_chunk += 1
        words_per_chunk_list.append(words_in_chunk)
        print(words_in_chunk)
        plot_wav_data(data_object, chunk[0], chunk[1])

    return words_per_chunk_list

def words_per_line(filepath):

    #ANALYZE WORDS PER LINE IN LYRIC FILE
    filename = "Strutter_expected.txt"
    words_per_line = []
    words = 0
    with open(filename, "r") as f:
        for line in f:
            for c in line:
                if c == " ":
                    words += 1
            words_per_line.append(words)
            words = 0

    return words_per_line

#create object, fill with data, and plot
strutter_vocals_data = Frequency_data("Strutter/Strutter - KISS_vocals.wav")
fill_data(strutter_vocals_data)
plot_wav_data(strutter_vocals_data)
'''
strutter_chunk_list = estimate_chunks(strutter_vocals_data.y_axis)

strutter_vocals_data.chunk_list = strutter_chunk_list
print(len(strutter_vocals_data.chunk_list))

words_per_chunk_list = estimate_words_per_chunk(strutter_vocals_data)

for entry in words_per_chunk_list:
    print(entry)

plot_wav_data(strutter_vocals_data)

#words_per_chunk_strutter = estimate_words_per_chunk(strutter_vocals_data)
#print(words_per_chunk_strutter)
'''
'''
rooster_vocals_data = Frequency_data("Rooster/Rooster - Alice in Chains_vocals.wav")
fill_data(rooster_vocals_data)

rooster_chunk_list = estimate_chunks(rooster_vocals_data.y_axis)

rooster_vocals_data.chunk_list = rooster_chunk_list
print(len(rooster_vocals_data.chunk_list))
for entry in rooster_vocals_data.chunk_list:
    print(entry[0]/44100, entry[1]/44100)

words_per_chunk_list = estimate_words_per_chunk(rooster_vocals_data)

for entry in words_per_chunk_list:
    print(entry)

plot_wav_data(rooster_vocals_data)

#words_per_chunk_strutter = estimate_words_per_chunk(strutter_vocals_data)
#print(words_per_chunk_strutter)
'''
