import matplotlib.pyplot as plt
import numpy as np
import scipy.io.wavfile as wavfile
from scipy.fftpack import fft, fftfreq

class Frequency_data():
    def __init__(self, filepath):
        self.filepath = filepath
        self.sample_rate = 0
        self.mono_normalized_data = []
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

    #CONVERT TO MONO
    data = np.mean(data, axis=1, dtype=data.dtype)

    #COMPUTE AXES (FOR TIME DOMAIN)
    x_axis = np.arange(0, len(data)/sample_rate, 1/sample_rate)
    y_axis = np.abs(data)

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
        if sample < 0.1:
            exclusions += 1
        else:
            avg_amp += float(sample)
    #divide by number of samples minus number of ignored samples
    avg_amp = avg_amp / ((len(y_axis) - exclusions)+0.00001)

    return avg_amp

def plot_time_domain(data_object, start_sample=0, end_sample=None, threshold=None):

    #if no end time is specified, default to the full runtime of the song
    if end_sample is None:
        end_sample = data_object.runtime*data_object.sample_rate

    #RECOMPUTE X AND Y AXES
    x_axis = data_object.x_axis[int(start_sample):int(end_sample)]
    y_axis = data_object.y_axis[int(start_sample):int(end_sample)]

    #ensure x and y axes are same length
    min_len = min(len(x_axis), len(y_axis))
    x_axis = x_axis[:min_len]
    y_axis = y_axis[:min_len]

    #compute average amplitude
    if threshold is None:
        threshold = compute_avg_amp(y_axis)

    #PLOT TIME DOMAIN
    plt.xlabel("Time (s)")
    plt.ylabel("Amplitude")
    plt.plot(x_axis, y_axis, '-')
    #plt.axhline(max_amp/2.3, color='green')
    plt.axhline(threshold, color='red')
    plt.show()

def plot_frequency_domain(data_object, start_sample=0, end_sample=None):

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
    
    #PLOT ORIGINAL FREQUENCY DOMAIN
    #set the maximum frequency shown on graph
    max_freq = 1000 ##~=22.05 kHz would be nyquist theorem val
    end = int(len(freqs) // (44100//max_freq))
    #half sampling frequency divided by number of samples
    x_axis = freqs[:end]
    y_axis = np.abs(fourier[:end])
    plt.subplot(2, 1, 1)
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

    plt.subplot(2, 1, 2)
    plt.xlabel("Frequency (Hz)")
    plt.ylabel("Amplitude (dB)")
    plt.plot(x_axis, y_axis, '-')
    plt.show()

def estimate_chunks(data_object):

    #FIND AVERAGE AMPLITUDE (EXLUDING SILENCES)
    avg_amp = compute_avg_amp(data_object.y_axis)

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
    for i, sample in enumerate(data_object.y_axis):
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
            #if silence has persisted for half a second
            if i - silence_start >= 44100/2:
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

    data_object.chunk_list = chunk_list

def estimate_words_per_chunk(data_object):
    
    words_per_chunk_list = []

    for chunk in data_object.chunk_list:

        y_axis = data_object.y_axis[chunk[0]:chunk[1]]

        avg_amp = compute_avg_amp(y_axis)
        threshold = avg_amp

        #COMPUTE ESTIMATED BLOCKS
        
        #FSM:
        #0 - CHECKING FOR START OF CHUNK
        #1 - CHECKING IF THIS IS TRULY A CHUNK OR JUST A RANDOM FREQUENCY SPIKE
        #2 - IF CHUNK_CHECK IS TRUE, SEARCH FOR END OF CHUNK
        #3 - STORE CHUNK WITH PROPER TIMESTAMP
        
        state = 0
        words_in_chunk = 0
        for i, sample in enumerate(y_axis):
            if state == 0:
                #IF THE START OF A CHUNK IS DETECTED
                if sample > threshold:
                    #GO TO NEXT STATE TO FIND SHORT SILENCE
                    start = i
                    state = 1
            elif state == 1:
                if sample < threshold:
                    silence_start = i
                    state = 2
            elif state == 2:
                #SILENCE = UNDER THRESHOLD FOR 0.1 SECOND
                if i - silence_start >= 44100/10:
                    state = 3
                #otherwise, assume we are still in the same word and revert to state 1
                elif sample >= threshold:
                    state = 1
            elif state == 3:
                #SCRAP IF WORD IS LESS THAN 0.2 SECONDS
                if silence_start - start < 44100/5:
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
        #plot_time_domain(data_object, chunk[0], chunk[1], threshold)

    return words_per_chunk_list

def estimate_words_energy(data_object):

    words_per_chunk = []
    frame_size = int(0.03 * data_object.sample_rate)
    step_size = int(0.01 * data_object.sample_rate)
    
    for chunk in data_object.chunk_list:

        y_axis = data_object.y_axis[chunk[0]:chunk[1]]

        energy = []

        #compute energy on per-frame basis
        for i in range(0, len(y_axis) - frame_size, step_size):
            frame = y_axis[i:i+frame_size]
            #RMS
            energy.append(np.sqrt(np.mean(frame**2)))

        #transfer to a numpy array
        energy = np.array(energy)

        #smooth and normalize signal
        window_size = 30
        smoothed = np.convolve(energy, np.ones(window_size)/window_size, mode='same')
        smoothed = smoothed / max(smoothed)
        x_smoothed = list(range(len(smoothed)))

        #detect valleys for word detection
        valleys = []

        for i in range(1, len(smoothed)-1):
            if smoothed[i] < smoothed[i-1] and smoothed[i] < smoothed[i+1]:
                valleys.append(i)

        #filter based on a tuned threshold
        threshold = 0.6  # tune this
        avg = 0
        for entry in smoothed:
            avg += entry
        avg = avg/len(smoothed)

        filtered_valleys = [i for i in valleys if smoothed[i] < threshold]
        words_per_chunk.append(len(filtered_valleys))

        '''
        print(f"ulfiltered valleys: {valleys}")
        print(f"filtered valleys: {filtered_valleys}")
        x_axis = list(range(len(y_axis)))
        plt.subplot(2, 1, 1)
        plt.plot(x_axis, y_axis)
        plt.subplot(2, 1, 2)
        plt.plot(x_smoothed, smoothed)
        plt.axhline(avg, color='red')
        plt.plot()
        plt.show()
        '''
    return words_per_chunk

def words_in_line(line):

    #ANALYZE WORDS PER LINE IN LYRIC FILE
    words = 0
    for c in line:
        if c == " ":
            words += 1

    return words
'''
#create object and fill with data
strutter_vocals_data = Frequency_data("Strutter/Strutter - KISS_vocals.wav")
fill_data(strutter_vocals_data)

#count the number of phrases and print their timestamps
estimate_chunks(strutter_vocals_data)

print(len(strutter_vocals_data.chunk_list))
for entry in strutter_vocals_data.chunk_list:
    print(entry[0]/44100, entry[1]/44100)

#plot for comparison to above
plot_time_domain(strutter_vocals_data)

#count number of words per phrase
estimate_words_energy(strutter_vocals_data)
'''
'''
#create object, fill with data, and plot
rooster_vocals_data = Frequency_data("Rooster/Rooster - Alice in Chains_vocals.wav")
fill_data(rooster_vocals_data)

#count the number of phrases and print their timestamps
estimate_chunks(rooster_vocals_data)

print(len(rooster_vocals_data.chunk_list))
for entry in rooster_vocals_data.chunk_list:
    print(entry[0]/44100, entry[1]/44100)

rooster_words_per_chunk = estimate_words_per_chunk(rooster_vocals_data)
print(rooster_words_per_chunk)

#plot for comparison to above
#plot_time_domain(rooster_vocals_data)

#count number of words per phrase
#estimate_words_energy(rooster_vocals_data)
'''
'''
#create object, fill with data, and plot
idontloveyou_vocals_data = Frequency_data("I Don't Love You/I Don't Love You - My Chemical Romance_vocals.wav")
fill_data(idontloveyou_vocals_data)

#count the number of phrases and print their timestamps
estimate_chunks(idontloveyou_vocals_data)

print(len(idontloveyou_vocals_data.chunk_list))
for entry in idontloveyou_vocals_data.chunk_list:
    print(entry[0]/44100, entry[1]/44100)

idontloveyou_words_per_chunk = estimate_words_per_chunk(idontloveyou_vocals_data)
print(idontloveyou_words_per_chunk)
'''
#create object, fill with data, and plot
#interstate_vocals_data = Frequency_data("Interstate Love Song/Interstate Love Song - Stone Temple Pilots_vocals.wav")
#fill_data(interstate_vocals_data)

#plot_time_domain(interstate_vocals_data)

#count the number of phrases and print their timestamps
#estimate_chunks(interstate_vocals_data)

#print(len(interstate_vocals_data.chunk_list))
#for entry in interstate_vocals_data.chunk_list:
    #print(entry[0]/44100, entry[1]/44100)

#interstate_words_per_chunk = estimate_words_per_chunk(interstate_vocals_data)
#print(interstate_words_per_chunk)

####
#FOR SYNCING LYRICS
#try to identify repeating lines because they will likely take the same amount of time to be sang!!!!!

def lyric_sync(data_object, lyric_file):

    synced_file = []
    total_lines = 0
    total_words = 0
    total_chunks = len(data_object.chunk_list)
    chunk_index = 0

    skip = 0
    i = 0

    with open(lyric_file, "r") as f:
        lines = f.readlines()
    with open(lyric_file, "r") as f:
        for line in f:
            total_words += words_in_line(line)
            total_lines += 1

    print("STARTING LYRIC SYNC\n\n\n")
    print(f"total lines: {total_lines}, total chunks: {total_chunks}")

    #if there significantly less chunks detected than there are actual lines of lyrics
    if (total_lines - total_chunks > 5):

        #find the average amount of time per known line in lyric file
        total_time_singing = 0
        for chunk in data_object.chunk_list:
            total_time_singing += chunk[1] - chunk[0]
        avg_time_per_word = total_time_singing / total_words / data_object.sample_rate
        print(f"time per word: {avg_time_per_word}")

        #create a list of the expected length of each individual chunk based on average time per word
        expected_chunk_lengths = []
        for line in lines:
            expected_chunk_lengths.append(words_in_line(line)*avg_time_per_word)

        #20% error per word length
        error_allowed = 0.2
            
        #here we will have to use chunks lengths to determine when lyrics are likely displayed
        j = 0
        while j < total_lines:

            #end process if index has exceeded the number of estimated chunks in the song
            if chunk_index >= len(data_object.chunk_list)-1:
                break

            current_timestamp = [round(data_object.chunk_list[chunk_index][0] / data_object.sample_rate, 1), round(data_object.chunk_list[chunk_index][1] / data_object.sample_rate, 1)]
            current_length = current_timestamp[1] - current_timestamp[0]

            #first check if this is a normally sized commit
            #given estimated time and an error window
            print(f"\n\n\ncurrent line: {lines[j]}")
            print(f"words in this line: {words_in_line(lines[j])}")
            print(f"low end of expected length: {expected_chunk_lengths[j]*(1-error_allowed)}, high end of expected length: {expected_chunk_lengths[j]*(1+error_allowed)}")
            print(f"actual length of line: {current_length}")

            written = 0
            possible_length = expected_chunk_lengths[j]
            extra_lines = 0
            while (not written):
                #see if the current line fits within or below the expected chunk length
                if (current_length < possible_length*(1+error_allowed)):
                    synced_file.append(f"[{current_timestamp[0]}] {' '.join(lines[j+k] for k in range(0, extra_lines+1))}")
                    j += extra_lines+1
                    written = 1
                #otherwise add next line length and check again
                else:
                    extra_lines += 1
                    possible_length += expected_chunk_lengths[j+extra_lines]

            chunk_index += 1

    else:

        for line in lines:

            line_written = 0

            if skip == 1:
                line_written = 1
                skip = 0

            #fail safe
            if chunk_index == total_chunks-1:
                break

            next_line = lines[i+1] if i+1 < len(lines) else ""

            words = words_in_line(line)
            next_words = words_in_line(next_line)

            while (not line_written):

                current_timestamp = [round(data_object.chunk_list[chunk_index][0] / data_object.sample_rate, 1), round(data_object.chunk_list[chunk_index][1] / data_object.sample_rate, 1)]
                next_timestamp = [round(data_object.chunk_list[chunk_index+1][0] / data_object.sample_rate, 1), round(data_object.chunk_list[chunk_index+1][1] / data_object.sample_rate, 1)] if chunk_index+1 < len(data_object.chunk_list) else [0, 0]
                current_length = current_timestamp[1] - current_timestamp[0]
                next_length = next_timestamp[1] - next_timestamp[0]
                additional = ''

                #first, check if the next set of words should be appended to the current
                if next_length > 2 and next_words <= 2:
                    line = line + ", " + next_line
                    skip = 1

                #now, check if we should skip this index (short phrases only)
                if current_length < 2:
                    if words > 2:
                        #chunk index will increase regardless, this simply skips appending
                        pass
                    #otherwise, it is likely that this 2 or less word line actually fits in this chunk!
                    else:
                        synced_file.append(f"[{current_timestamp[0]}] {line} {additional}")
                        line_written = 1
                    #increase index
                    chunk_index += 1
                #otherwise, this is a > 2 second phrase
                else:
                    if words <= 2:
                        #there will need to be another check implemented here with CUSTOM ESTIMATED WORDS
                        chunk_index += 1
                    else:
                        synced_file.append(f"[{current_timestamp[0]}] {line}")
                        line_written = 1
                        chunk_index += 1
            i += 1
    

    with open(f"{data_object.filepath}_timestamps.txt", "w") as f:
            for line in synced_file:
                f.write(line)

#lyric_sync(idontloveyou_vocals_data, "I Don't Love You/I Don't Love You_lyrics_finalized.txt")
#lyric_sync(strutter_vocals_data, "Strutter_lyrics_finalized.txt")
#lyric_sync(interstate_vocals_data, "Interstate Love Song/Interstate Love Song_lyrics_finalized.txt")
