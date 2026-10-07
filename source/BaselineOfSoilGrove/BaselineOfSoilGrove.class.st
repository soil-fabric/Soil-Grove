Class {
	#name : #BaselineOfSoilGrove,
	#superclass : #BaselineOf,
	#category : #BaselineOfSoilGrove
}

{ #category : #baselines }
BaselineOfSoilGrove >> baseline: spec [
	<baseline>

	spec for: #'common' do: [
		self soil: spec.

		spec package: #'Soil-Queue' with: [ spec requires: #('Soil') ].
		spec package: #'Soil-Queue-Tests' with: [ spec requires: #('Soil-Queue') ] ].

	spec 
		group: 'tests' with: #('Soil-Queue-Tests');
		group: 'queue' with: #('Soil-Queue');
		group: 'default' with: #('queue' 'tests')
]

{ #category : #baselines }
BaselineOfSoilGrove >> soil: spec [

	spec baseline: 'Soil' with: [
		spec
			repository: 'github://ApptiveGrid/Soil:808a6c0e9d41ff31ce70f3b71d4011f6b1e3ec93/src' ]
]
