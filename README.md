# genea-crypto

_Tools for genealogical research._

I'll be adding scripts and other stuff that I use to assist me in my
genealogical research.

Right now, only a Perl script to parse an
[Ahnentafel](https://en.wikipedia.org/wiki/Ahnentafel) txt file in Spanish that
I was given (which was created using [PAF](https://familysearch.org/paf).

A sample portion of the input file:
```
    20. Firstname Lastname Secondlastname nació en Sant Feliu de Codines.  Él murió en Sant Feliu de Codines. Firstname se casó con Firstname2 Lastname2 Secondlastname2 el 11 Octubre 1799 en Sant Feliu de Codines.


    21. Firstname2 Lastname2 Secondlastname2 nació en Sant Quirze de Besora. Ella murió en Sant Feliu de Codines.
```

It produces an Gramps XML file with people, families, events, notes and places
than can be readily imported into Gramps.
