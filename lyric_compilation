from difflib import SequenceMatcher

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

    '''
    for line in visual_comparison:
        print(line)
    '''

    #FUTURE IDEA IF NECESSARY:
    #keep an overall confidence score match for each line; if a match isnt found for a number of iterations it is automatically removed from contention
    #PRETTY SURE IT MAKES SENSE THAT IF I =/ 0 IS A MATCH JUST DROP EVERY LINE PRIOR TO I
    #first try to organize and match lines as necessary
    confidence_score = 0
    for i in range(0, medium_total_lines):

        #collect similarity scores for 
        base_scores = [similarity_score(x, medium_text[i]) for x in base_text[:3]]
        small_scores = [similarity_score(x, medium_text[i]) for x in small_text[:3]]
        print(medium_text[i])
        print(base_scores, small_scores)

        best_base_score, best_base_index = 0, 0
        best_small_score, best_small_index = 0, 0
        
        for j, score in enumerate(base_scores):
            if score > best_base_score:
                best_base_score = score
                best_base_index = j
        for j, score in enumerate(small_scores):
            if score > best_small_score:
                best_small_score = score
                best_small_index = j
        
        print(best_base_score, best_small_score)
        if best_base_score < 0.5 and best_small_score < 0.5:
            print(i)
            if i == 0:
                final_text.append(medium_text[i])
                confidence_score += 0
        else:
            final_text.append(medium_text[i])
            confidence_score += max(best_base_score, best_small_score)
            if best_base_score > 0.5:
                print(base_text[best_base_index])
                base_text.pop(best_base_index)
            if best_small_score > 0.5:
                print(small_text[best_small_index])
                small_text.pop(best_small_index)

        with open(songname+"_lyrics_finalized.txt", "w") as f:
            for line in final_text:
                f.write(line)

lyric_compile("Rooster")
