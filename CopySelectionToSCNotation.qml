import QtQuick 2.0
import MuseScore 3.0

MuseScore {
    menuPath: "Edit.CopyToSCNotation"
    description: "Copy Current Selection or score to SuperCollider Pattern Notation - midinote, dur, sustain"
    version: "1.0"

    // CONSTANTS
    readonly property var _INSTRUMENT: "Instrument"
    readonly property var _NOTES: "Notes"
    readonly property var _START: "Start"
    readonly property var _DURATION_TICKS: "Duration Ticks"
    readonly property var _DURATION_STRING: "Duration String"
    readonly property var _REST: "Rest"

    readonly property var _NULL : -1;

    // Tempo independent - for now we assume that a 64th note is the minimum note length we could possibly have.
    readonly property var _WHOLE_NOTE_DURATION: 1920
    readonly property var _HALF_NOTE_DURATION: 960
    readonly property var _QUARTER_NOTE_DURATION: 480
    readonly property var _EIGHTH_NOTE_DURATION: 240
    readonly property var _16TH_NOTE_DURATION: 120
    readonly property var _32ND_NOTE_DURATION: 60
    readonly property var _64TH_NOTE_DURATION: 30

    readonly property var durationMap:  {
        1: _WHOLE_NOTE_DURATION,
        2: _HALF_NOTE_DURATION,
        4: _QUARTER_NOTE_DURATION,
        8: _EIGHTH_NOTE_DURATION,
        16: _16TH_NOTE_DURATION,
        32: _32ND_NOTE_DURATION,
        64: _64TH_NOTE_DURATION,
    }

    // Invisible Text Edit Object to Access System Clipboard
    // https://stackoverflow.com/questions/59806339/qml-listview-how-to-copy-selected-item-to-clipboard/59806775#59806775
    TextEdit{
        id: sc_output;
        visible: false
    }

    /*  This script will get the notes and their durations from the current selection
     *  translate them into Supercollider pattern notation, and copy the values to the clipboard.
     *  The scope includes *only* notes and rests.
     *
     *  NB: Grace notes are not included for this iteration of the script.
     *
     *  Output is broken out by MuseScore instrument ID and voice. Pdefs may allow for chords, and multiple voices,
     *  but for any sort of real, human comprehension of what's happening inside of a Pattern, breaking it into multiple
     *  voices is best for readability. This may change in the future, but for now, we are including the voice number, as
     *  well as the instrument ID as the unique identifier for the voice map.
     */

    onRun: {

        var instrumentMap = {}

        // TODO: apply to the entire score.

        var currentSelection = []
        var cursor = curScore.newCursor();
        var startTick = _NULL;

        for (var i in curScore.selection.elements) {

            if (curScore.selection.elements[i].type == Element.NOTE) {

                var note = curScore.selection.elements[i];
                var segment = note.parent;
                var instrumentName = camelize(segment.staff.part.longName);
                var instrumentTrack = segment.staff.part.startTrack / 4;
                var instrumentVoice = getVoice(note, cursor, segment.parent.tick);
                var instrumentStaff = getStaff(note, cursor, instrumentTrack, segment.parent.tick);
                var uniqueInstrumentIdentifier = instrumentName + "_" + instrumentTrack + "_" + instrumentVoice + "_" + instrumentStaff;

                // Common Methods to be added for later use
                var segmentStart;
                var durationTicks;
                var durationString;

                // If the note has a tieForward and does not have a tieBack, that means it's the first note in a tied sequence. I am making the decision that
                // even if the note is in a tied sequence and the entire tied sequence is not selected, then the length of the tied sequence will be applied to
                // the Pdef definition. Similarly, if a tie-back is found on a note, the note will be skipped as it's part of a larger tie that's being consumed.
                // This is to create the least surprise possible.
                if (note.tieForward != null && note.tieBack == null) {

                    var segmentStart = segment.parent.tick;
                    var lastNoteSegment = note.lastTiedNote.parent;
                    var lastNoteSegmentStart = lastNoteSegment.parent.tick;
                    var lastNoteSegmentLength = lastNoteSegment.duration.ticks;
                    var lastNoteSegmentEnd = lastNoteSegmentStart + lastNoteSegmentLength;
                    var tiedNoteDuration = lastNoteSegmentEnd - segmentStart;
                    var durationDenominator = segment.duration.denominator;

                    // If we have a tied note, we want to have a representation like 3/8 instead of 1.5/4
                    // This will continue to increase the denominator until both numbers are whole.
                    while(tiedNoteDuration % durationMap[durationDenominator] > 0) {
                        durationDenominator = durationDenominator * 2;
                    }

                    var numerator = tiedNoteDuration/durationMap[durationDenominator];
                    var denominator = durationDenominator;

                    durationTicks = tiedNoteDuration;
                    durationString = simplifyFractionToString(numerator, denominator);
                } else if (note.tieBack != null) {
                    // If we have a tie back, we're skipping the note.
                    continue;
                } else {
                    segmentStart = segment.parent.tick;
                    durationTicks = segment.duration.ticks;
                    durationString = segment.duration.str;
                }

                // Create a dictionary at this tick for the instrument identifier so
                // we can order the data later.
                addIfNotExists(instrumentMap, uniqueInstrumentIdentifier)
                addInstrumentDetails(segmentStart, instrumentMap[uniqueInstrumentIdentifier])
                var tickMap = instrumentMap[uniqueInstrumentIdentifier][segmentStart]

                // When we get to creating the pdefs, we need to know where to put the phase for each pattern.
                // Phase is an offset of the start, so we need to know where the start is.
                if (segmentStart < startTick || startTick == _NULL) {
                    startTick = segmentStart;
                }

                // Add Note Information To Maps At Tick to ensure ordering when generating output.
                // Unclear if ordering will ever be non-deterministic when accessing the API

                // Concert Pitch - Midi Notes are in Concert Pitch Regardless of Status
                tickMap[_NOTES].push(note.pitch)

                // Duration in ticks, used to find the smallest duration to determine when the next element should play
                if (tickMap[_DURATION_TICKS][0] == undefined) {
                    tickMap[_DURATION_TICKS].push(durationTicks)
                }
                // Duration of each element in musical terms. Should be able to be pasted into SC as-is.
                if (tickMap[_DURATION_STRING][0] == undefined) {
                    tickMap[_DURATION_STRING].push(durationString)
                }

            } else if (curScore.selection.elements[i].type == Element.REST) {
                var rest = curScore.selection.elements[i];
                var segment = rest.parent
                var instrumentName = camelize(rest.staff.part.longName);
                var instrumentTrack = rest.staff.part.startTrack / 4;
                var instrumentVoice = getVoice(rest, cursor, segment.tick);
                var instrumentStaff = getStaff(rest, cursor, instrumentTrack, segment.tick);
                var uniqueInstrumentIdentifier = instrumentName + "_" + instrumentTrack + "_" + instrumentVoice + "_" + instrumentStaff;

                // When we get to creating the pdefs, we need to know where to put the phase for each pattern.
                // Phase is an offset of the start, so we need to know where the start is.
                if (segment.tick < startTick || startTick == _NULL) {
                    startTick = segmentStart;
                }

                var durationString = simplifyFractionToString(rest.duration.numerator, rest.duration.denominator);

                // Add Note Information To Maps At Tick to ensure ordering when generating output.
                // Unclear if ordering will ever be non-deterministic when accessing the API
                addIfNotExists(instrumentMap, uniqueInstrumentIdentifier)
                addInstrumentDetails(segment.tick, instrumentMap[uniqueInstrumentIdentifier])
                var tickMap = instrumentMap[uniqueInstrumentIdentifier][segment.tick]

                // Add Note Information To Maps At Tick
                tickMap[_NOTES].push(_REST);
                if (tickMap[_DURATION_TICKS][0] == undefined) {
                    tickMap[_DURATION_TICKS].push(rest.duration.ticks);
                }
                if (tickMap[_DURATION_STRING][0] == undefined) {
                    tickMap[_DURATION_STRING].push(durationString);
                }

            } else {
                // UNHANDLED TYPE
            }
        }

        // Now that we've got the information in for each instrument, let's print it out into a
        // form that's digestible by SuperCollider.

        // Get Time Signature so we know what the phase is. We will use the offset from the first
        // measure, making the assumption that the time signature will remain consistent. This is
        // *not* something that's particularly useful for more complex music and will be a TODO
        // once I understand complex meter in Supercollider.
        //
        // NB: This is currently unused as it looks like all of the selection is properly phased,
        // but I don't trust it.
        cursor.rewindToTick(startTick);
        var timeSignature = cursor.measure.timesigActual;
        var timeSignatureBeatTicks = durationMap[timeSignature.denominator];

        // Output Holder
        sc_output.text = "(\n";

        for (var instrument in instrumentMap) {
            var note_output_value="~" + instrument + "_notes = [";
            var duration_output_value="~" + instrument + "_durations = [";
            var phase_output_value="~" + instrument + "_phase = 0";

            // The selection emplaces what looks like a sorted list, but we can't guarantee
            // that this is correct. Putting in the sort to ensure we get values in tick order.
            var sortedMapKeys = sortMapKeys(instrumentMap[instrument]);
            var instrumentStartTick = sortedMapKeys[0];

            // Add note and rest details order by tick
            for (var i in sortedMapKeys) {
                var tick = sortedMapKeys[i];
                tickMap = instrumentMap[instrument][tick];
                note_output_value=note_output_value + tickMap[_NOTES] + ",";
                duration_output_value=duration_output_value + tickMap[_DURATION_STRING] + ",";
            }

            // Remove last comma
            note_output_value=note_output_value.slice(0, -1) + "]"
            duration_output_value=duration_output_value.slice(0, -1) + "]"

            // Add to formatted output
            sc_output.text = sc_output.text + note_output_value + ";\n";
            sc_output.text = sc_output.text + duration_output_value + ";\n";
            sc_output.text = sc_output.text + phase_output_value + ";\n";
        }

        sc_output.text = sc_output.text +");";

        // Copy to system clipboard
        sc_output.selectAll();
        sc_output.copy();

        Qt.quit()
    }

    // Helper functions

    function addInstrumentDetails(tick,instrumentMap) {
        if (instrumentMap[tick] == undefined) {
            // Create Associative Map of Details
            var instrumentDetails = {};
            instrumentDetails[_NOTES] = [];
            instrumentDetails[_DURATION_TICKS] = [];
            instrumentDetails[_DURATION_STRING] = [];
            instrumentMap[tick] = instrumentDetails;
        }
    }

    function addIfNotExists(map, key) {
        if (map[key] == undefined) {
            map[key] = {};
        }
    }

    function getVoice(element, cursor, tick) {
        cursor.track = element.track;
        cursor.rewindToTick(tick);
        return cursor.voice;
    }

    function getStaff(element, cursor, instrumentTrack, tick) {
        cursor.track = element.track;
        cursor.rewindToTick(tick);
        return cursor.staffIdx - instrumentTrack;
    }

    function simplifyFractionToString(numerator, denominator) {
        // Using https://en.wikipedia.org/wiki/Greatest_common_divisor#Euclidean_algorithm
        // A more efficient method is the Euclidean algorithm, a variant in which the difference
        // of the two numbers a and b is replaced by the remainder of the Euclidean division
        // (also called division with remainder) of a by b.

        // Denoting this remainder as a mod b, the algorithm replaces (a, b) by (b, a mod b)
        // repeatedly until the pair is (d, 0), where d is the greatest common divisor.

        //For example, to compute gcd(48,18), the computation is as follows:
        // gcd(48, 18) -> gcd(18, 48 % 18) = gcd(18, 12)
        //             -> gcd(12, 18 % 12) = gcd(12, 6)
        //             -> gcd(6, 12 % 6) = gcd(6, 0);
        //
        // This gives gcd(48, 18) = 6.


        // Take care of the obvious edge case
        if (numerator == denominator) {
            return "1";
        }

        var a = numerator;
        var b = denominator;
        var tmp;

        while(a % b > 0) {
            tmp = b;
            b = a % b;
            a = tmp;
        }

        if (denominator/b == 1) {
            return numerator/b;
        } else {
            return (numerator/b +  "/" + denominator/b);
        }
    }

    // From: https://stackoverflow.com/questions/1069666/sorting-object-property-by-values
    function sortMapKeys(obj) {
        var arr = [];
        for (var prop in obj) {
            if (obj.hasOwnProperty(prop)) {
                arr.push(prop);
            }
        }
        arr.sort(function(a, b) { return a - b; });
        return arr;
    }

    // From: https://stackoverflow.com/questions/2970525/converting-any-string-into-camel-case
    // We need to make sure the instrument names are in camelCase so they meet the critera for
    // supercollider variable names.
    function camelize(str) {
        return str.toLowerCase().replace(/[^a-zA-Z0-9]+(.)/g, (m, chr) => chr.toUpperCase());
    }
}
