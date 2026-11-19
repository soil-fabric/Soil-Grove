"
What an embedder connects to a lane (SoilQueue>>#gate:forLane:) to limit how many entries
leave it: a rate, a plan's quota, whatever the embedder counts. I am the contract, and I am
open -- the gate a lane has when nobody connected one -- so that the queue never asks
whether there is one.

Three questions, and what the queue does with each:

#allowanceAt: how many entries may leave the lane at that time; 0 is shut. Asked before
an entry is chosen, and by the dispatcher to know how many workers are worth starting.

#nextOpenAfter: when a shut gate can open again, or nil when it cannot say. Asked only
when the allowance is 0, for the time the dispatcher has to be awake.

#take one entry has left the lane, and I use up what that costs. Told once for every entry
that was handed out, and never when nothing was found. It is the only message that
changes me.

I am behaviour and not a setting: I am not stored, and not part of the queue's
description. My subclasses answer from whatever their embedder counts; they are asked
under the queue's mutex, so they are not to wait for anything.
"
Class {
	#name : #SoilQueueGate,
	#superclass : #Object,
	#category : #'Soil-Queue'
}

{ #category : #accessing }
SoilQueueGate >> allowanceAt: aDateAndTime [
	"as many as anyone asks for: no bound of my own, a number no lane has places for"

	^ 1 << 30
]

{ #category : #accessing }
SoilQueueGate >> nextOpenAfter: aDateAndTime [
	"never shut, so there is nothing to wait for"

	^ nil
]

{ #category : #accessing }
SoilQueueGate >> take [
	"nothing to use up"
]
