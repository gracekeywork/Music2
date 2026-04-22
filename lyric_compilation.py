from difflib import SequenceMatcher
#model choices:
#base ~ no, small ~ 3.5min, medium ~ 3.5min, large ~ no, turbo ~ prob no

def similarity_score(line1, line2):
    return SequenceMatcher(None, line1, line2).ratio()

def lyric_compile(songname):

    print("\n\n\nBEGINNING LYRIC COMPILATION\n\n\n")

    base_file = songname+"_base.txt"
    small_file = songname+"_small.txt"
    medium_file = songname+"_medium.txt"

    base_text, small_text, medium_text, final_text = [], [], [], []

    visual_comparison = []

    with open(base_file, "r") as f:
        for i, line in enumerate(f):
            visual_comparison.append(line)
            base_text.append(line)

    with open(small_file, "r") as f:
        for i, line in enumerate(f):
            if i < len(visual_comparison):
                visual_comparison[i] = visual_comparison[i] + "    "+line
            else:
                visual_comparison.append(line)
            small_text.append(line)

    with open(medium_file, "r") as f:
        for i, line in enumerate(f):
            if i < len(visual_comparison):
                visual_comparison[i] = visual_comparison[i] + "    "+line
            else:
                visual_comparison.append(line)
            medium_text.append(line)
            medium_total_lines = i+1

    #BEFORE BEGINNING, ALIGN FILES AS BEST AS POSSIBLE
    base_aligned = 0
    small_aligned = 0
    base_start_index = 0
    small_start_index = 0
    starting_window = 7

    i = 0
    while (not base_aligned and i <= starting_window):
        base_scores = [similarity_score(x, medium_text[i]) for x in base_text[:starting_window]]
        for j, score in enumerate(base_scores):
            if score > 0.5:
                print(i, j+i, base_text[j+1])
                base_start_index = j-i
                base_aligned = 1
                break
        i += 1
    if i-1 - base_start_index > 0:
        padding = [""] * (i-1 - base_start_index)
        base_text = padding + base_text
    else:
        base_text = base_text[base_start_index:]

    i = 0
    while (not small_aligned and i <= starting_window):
        small_scores = [similarity_score(x, medium_text[i]) for x in small_text[:starting_window]]
        for j, score in enumerate(small_scores):
            if score > 0.5:
                small_start_index = j-i
                small_aligned = 1
                break
        i += 1
    if i-1 - small_start_index > 0:
        padding = [""] * (i-1 - small_start_index)
        small_text = padding + small_text
    else:
        small_text = small_text[small_start_index:]


    #FUTURE IDEA IF NECESSARY:
    #keep an overall confidence score match for each line; if a match isnt found for a number of iterations it is automatically removed from contention
    #PRETTY SURE IT MAKES SENSE THAT IF I =/ 0 IS A MATCH JUST DROP EVERY LINE PRIOR TO I
    #first try to organize and match lines as necessary
    confidence_score = 0
    base_stuck_counter = 0
    small_stuck_counter = 0
    stuck_threshold = 3
    for i in range(0, medium_total_lines):

        print("\nNEW ROUND\n")

        #collect similarity scores for 
        base_scores = [similarity_score(x, medium_text[i]) for x in base_text[:3]]
        small_scores = [similarity_score(x, medium_text[i]) for x in small_text[:3]]
        print("medium text: "+medium_text[i])
        if len(base_text) != 0 and len(small_text) != 0:
            print("aligned base and small: "+base_text[0]+" "+small_text[0])

        best_base_score, best_base_index = 0, 0
        best_small_score, best_small_index = 0, 0
        
        #determine the best score for both the base comparisons and small comparisons
        for j, score in enumerate(base_scores):
            if score > best_base_score:
                best_base_score = score
                best_base_index = j
        for j, score in enumerate(small_scores):
            if score > best_small_score:
                best_small_score = score
                best_small_index = j
        
        if len(base_text) != 0 and len(small_text) != 0:
            print(f"base line and score: {base_text[best_base_index]} {best_base_score}")
            print(f"small line and score: {small_text[best_small_index]} {best_small_score}")

        #if neither score is above 0.5
        if best_base_score < 0.5 and best_small_score < 0.5:
            #when i = 0, still keep the first line of medium; it is usually right
            if i == 0:
                final_text.append(medium_text[i])
                confidence_score += 0

            if best_base_score < 0.5:
                base_stuck_counter += 1
                #IF BASE HAS BEEN STUCK FOR stuck_threshold ITERATIONS, DROP THOSE +1 ENTRIES
                if base_stuck_counter == stuck_threshold:
                    #--REALIGNMENT IF STUCK TOO LONG--
                    # Search ahead up to 10 lines in base_text for a match to current medium_text[i]
                    lookahead = 10
                    search_window = base_text[:lookahead]
                    scores = [similarity_score(x, medium_text[i]) for x in search_window]
                    
                    if scores and max(scores) > 0.5:
                        best_match = scores.index(max(scores))
                        print(f"Found match in base at +{best_match}. Re-aligning.")
                        base_text = base_text[best_match:] # Snap to that line
                    else:
                        # If no match found, fall back to original 3-line jump
                        base_text = base_text[stuck_threshold:]
                    base_stuck_counter = 0 # Reset counter after realigning

            if best_small_score < 0.5:
                small_stuck_counter += 1
                if small_stuck_counter == stuck_threshold:
                    if small_stuck_counter == stuck_threshold:
                        print(f"!!! Small stuck for {stuck_threshold} rounds. Re-aligning...")
                        lookahead = 10
                        search_window = small_text[:lookahead]
                        scores = [similarity_score(x, medium_text[i]) for x in search_window]
                        
                        if scores and max(scores) > 0.5:
                            best_match = scores.index(max(scores))
                            print(f"Found match in small at +{best_match}. Re-aligning.")
                            small_text = small_text[best_match:]
                        else:
                            small_text = small_text[stuck_threshold:]
                        small_stuck_counter = 0

        else:
            final_text.append(medium_text[i])
            confidence_score += max(best_base_score, best_small_score)
            #when the base score is considered accurate
            if best_base_score > 0.5:
                base_stuck_counter = 0
                print(f"removing: {base_text[best_base_index]}")
                #+1 so as to remove the best_base_index line as well
                base_text = base_text[best_base_index+1:]
            #when the small score is considered accurate
            if best_small_score > 0.5:
                small_stuck_counter = 0
                print(f"removing: {small_text[best_small_index]}")
                small_text = small_text[best_small_index+1:]

        final_text_length = 0
        with open(songname+"_lyrics_finalized.txt", "w") as f:
            for line in final_text:
                final_text_length += 1
                f.write(line)
    
    confidence_score = confidence_score / final_text_length

    print(f"Compiled lyrics confidence score: {confidence_score}")

filename = "Interstate Love Song/Interstate Love Song - Stone Temple Pilots.wav"
