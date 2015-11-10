# Thesis Titles

* You Can't Spell Trust Without Rust
* Shared Mutability Kills Freedom and Leads to Communism
* Designing APIs for Data-Trust



# Abstract

Rust is a new systems programming language that aims to be safe, fast, and
ergonomic. We explore how Rust accomplishes this through *ownership*.



# Introduction

Rust is a new programming language with ambitious goals: in principle, Rust
is faster than C++, safer than Java, and easier to develop in than
both! Rust also enables programmers to be fearless in the face of
concurrency and parallelism.

These are bold claims. What possible mechanism could enable this? Well, nothing
on its own is *truly* sufficient to make these claims. Rust largely just steals good
ideas from wherever it finds them. Piecewise, Rust isn't a particularly novel
language. This was in fact a specific design goal, because research is hard and slow.
As a whole, however, Rust has developed some interesting systems and insights.
The most important of these is *ownership*. Rust models data ownership in a
first-class manner unlike any other language in production today. To our knowledge,
the closest language to Rust in this regard is [Cyclone][], which is no coincidence.
Rust has sourced many great ideas from Cyclone.

However Cyclone was largely trying to be as close as possible to C. As such,
many aspects of ownership weren't as well integrated or fleshed out as in Rust,
as legacy constraints got in the way. Cyclone has also unfortunately been
officially abandoned, and is no longer maintained or supported. By contrast,
Rust 1.0 was released last year, and the language has been going strong ever
since.

This thesis focuses on Rust's ownership system, the systems it can express,
and its limitations. However, in order to properly understand ownership, we
must first understand its motivation.



# Safety and Correctness

Programming is hard. \[citation needed\]

We would like our programs to be correct, but we seem to be very bad at doing
this. In fact, any assertion that a non-trivial program is totally correct
will be met with deep suspicion. This isn't unreasonable: any non-trivial property
one might be interested in is usually undecidable in even trivial programming
languages. Still, some bugs are more pervasive and pernicious than others.
It's one thing to get a poorly rounded display value, but another thing altogether
to join a botnet because of an insecure integer parser.

For this reason, it is common to distinguish one major category of bug from
all others: *memory safety*. A system is memory-safe if access to memory is
properly restricted. This is an unfortunately vague definition, but that's because
it's a broad problem. At the heart of memory safety are two major concerns:
preventing secrets from being stolen, and systems from being hijacked. It is
of course possible to design a memory-safe system that liberally leaks secrets
and happily takes arbitrary commands from the public internet, but an absence
of memory safety makes even innocuous systems trivial to hijack in this way.

Most importantly, programs must have *some* restriction on what can be read
and written by what. If a function can freely read and write all the memory
in a process, then compromising that function can make it do almost certainly
anything and everything. In particular, overwriting return pointers in a
program's call stack can often enable an attacker to execute arbitrary
computations, even in a system with proper code-data separation and address
space layout randomization.

Even "only" being able to read arbitrary memory can be an exploit, particularly
as reading memory often implies writing the value somewhere else. This is the
basis for the infamous Heart Bleed attack, where clients could ask servers
to send them random chunks of its memory, leaking the server's private key.

Upholding memory safety is a difficult task that must often be approached in
a holistic manner. Two interfaces that are memory-safe on their own can easily
be unsound when combined.

In addition to the matter of memory safety, there is also the broader problem
of overall correctness. It is of course impossible for a system to enforce
that all programs are correct, because it requires the programmer to
correctly interpret and encode their program's requirements, which
the system can't possibly evaluate the accuracy of. That said, it is possible
for a system to understand common errors and make those harder. For instance,
few programs expect integers to overflow, so a system that does more to prevent
or mitigate integer overflow may be regarded as safer.

Rust is first and foremost dedicated to being memory-safe at all costs, but is
also tries to be safer in general. All else equal, if an interface can
prevent misuse, that's a good thing to have. The question is if all else is
*really* equal, or if preventing an error comes at significant ergonomic or
performance costs.

While the techniques demonstrated in this thesis are can be applied generally,
we will be focusing on few particular common problems that can lead to
memory safety violations: use-after-free, iterator invalidation, and indexing
out of bounds. In addition, we will consider the problem of memory leaks, which
aren't a memory-safety problem, but still problematic.

We will see how all of these problems occur in the two most prolific programming
languages of all: C and C++. It's worth noting that the practices encouraged
by "modern" C++ can significantly mitigate or eliminate these errors, but
unfortunately these are only conventions, and must be rigorously followed
and understood to work correctly. A C++ programmer who is unaware of these
practices gains little safety from using the latest C++ release, particularly
since the unsafe practices are often the most convenient and well-supported.

Bjarne Stroustrup and Herb Sutter recently announced an experimental system
built on top of C++ that claims to statically enforce that programs are memory-
safe, but not enough is currently known to comment on the viability or soundness
of this system. From what we've seen, it actually hews quite close to Rust, but
like Cyclone, it appears to be significantly burdened by C++'s legacy semantics.




## Use-After-Free

A use-after-free is one of the two canonical memory safety violations. It
occurs when some memory is marked as unused (freed), but the program
continues to use that memory. Here's two simple versions of this problem, as
seen in C:

```C
#include <stdlib.h>
#include <stdio.h>

// use-after-free with heap allocation
int main() {
    // Get some memory from the allocator
    char* string = (char*) calloc(3, 1);
    string[0] = 'h';
    string[1] = 'i';

    // Give the memory back to the system allocator
    free(string);

    // Use the memory anyway
    printf("%s\n", string);
}
```

```C
#include <stdio.h>

// use-after-free with stack allocation
int main() {
    char* ptr = 0;

    if (!ptr) {
        char data = 17;
        // take a pointer to `data`
        ptr = &data;
    }
    // data is now out of scope, and undefined

    // read it anyway
    printf("%u\n", *ptr);
}
```

In principle, a use-after-free can be harmless if the code in question gets lucky.
The system may never look at this memory again, allowing it to continue to
behave in an allocated manner. However the system has been given permission
to do whatever it pleases with this memory, which can lead to several problems.

First, the memory can be returned to the operating system. If memory returned
to the OS is used, this will cause a page fault, causing the program to crash.
This is annoying, but is arguably memory-safe in the sense that the memory
is never successfully used after it is freed. The problematic case is when the
allocator *reuses* the memory. Any subsequent allocation may receive the
freed memory, leading the memory to be used for two different purposes. This
violates memory safety, allowing code to read or write memory that it wasn't
supposed to.

Use-after-frees are solved by almost all languages by requiring
pervasive garbage collection. C and C++ are the two major exceptions, which
by default don't use any garbage collection mechanisms. In these two languages
the use-after-free is a rich source of exploits to this day. As we will
see, this is no coincidence. The solution taken by most languages is
unacceptable to those who traditionally use C or C++.

Use-after-frees are the canonical example of the more general problem of
using something after it has been logically destroyed. For instance, a similar
problem applies to using file handles after they're closed. However the
use-after-free is particularly problematic because most system allocators
pool and reuse pages of memory acquired from the OS. This prevents the OS from
understanding that memory is supposed to be unused.

File handles, on the other hand, are generally not pooled like this. T
hat said, it's possible for new handles to match the value of old handles
(like pointers, they're ultimately just integers). This can lead to a similar
scenario as a use-after-free, where two distinct handles are independently
trying to use the same file.

The more general category reveals a fundamental weakness of garbage collection:
it only solves a use-after-free, and no other kind of use-after. Most languages
therefore require runtime checks to guard against this problem in the general
case. Regardless of if one gets particularly lucky or guards against this error
at runtime, any program that tries to use-after is certainly *wrong*, and we would
like our programs to be correct.





## Index Out Of Bounds

An index out of bounds is the second canonical memory safety violation. It
occurs when the index used to access an array is too large or small. A simple
C version:

```C
#include <stdio.h>

int main() {
    // An array of 5 elements
    char data[5] = {1, 2, 3, 4, 5};

    // Print out the 17th element
    printf("%u\n", data[17]);
}
```

The consequence of an index out of bounds is quite straight-forward: it reads
or writes memory that happens to be near the array as if it were an
element of that array. For arrays sitting on the stack, this is an easy vector
for overwriting a function's return pointer.

Like general use-afters, this problem is usually resolved through runtime
checks. Every operation that takes an index compares it to the length of the
array. However C and C++ provide no guards by default, and in some cases array
length isn't even known, making it *impossible* to check.





## Iterator Invalidation

Iterator invalidation because it's similar to a use-after-free or indexing
out of bounds, but can require more pervasive checking to guard against. This
problem occurs when a data structure is mutated while it is being iterated. A
simple example in C++:

```C++
#include <vector>
#include <stdio.h>
using namespace std;

int main() {
    // a growable array of four 5's
    vector<char> data (4, 5);

    // loop over the array to print the elements out
    for (auto it = data.begin(); it != data.end(); ++it) {
        printf("%u\n", *it);

        // but push a single element onto the stack while doing it
        if (it == data.begin()) {
            data.push_back(0);
        }
    }
}
```

When an iterator is invalidated it will start acting on
outdated information, potentially stomping through memory that is no longer
part of the collection. For instance, when we executed this program it produced
22(!) values. Evidently the array's backing storage had been reallocated
in a different location on the heap, conveniently only a few bytes over. The `it`
variable simply walked forward through the heap until it found the new end of
the array. In other words, we managed to index out of bounds *and* use-after-free
at the same time.

Even if an iterator isn't invalidated in this process, mutating a collection
while iterating it is an easy way to produce a nonsensical program. For instance,
unconditionally inserting into a collection while iterating into it may lead
to an infinite memory-consuming loop. That said, it can be be desirable to
mutate a collection while iterating it. For instance, one may wish to process all
the elements in an array, removing those that don't meet some condition.

In order to guard against this, any operations which can invalidate an iterator
need to somehow know about any outstanding iterators or otherwise signal to
them that a change has been made. One way to do this is to have the
collection contain a timestamp of when it was last modified which iterators
repeatedly verify hasn't changed. This is exactly how OpenJDK's ArrayList is
implemented. [jdk-iter][]

Once again, neither C nor C++ provide any guards against this sort of thing
by default.

Iterator invalidation can be generalized to the invalidation of any "view"
into another type. Iterators are particularly nasty because they're often
low-level and performance sensitive, but any view can be made
inconsistent by mutating what it intends to represent.




## Memory Leaks

Memory leaks are unlike any of the other errors above. The other errors are a matter
of doing a thing that shouldn't have been done. Leaks, on the other hand, are
failing to do something that *should* have been done. In contrast to a
use-after-free, a leak occurs when memory is *never* returned to the allocator.
We can demonstrate a memory leak by just removing the call to `free` from our
use-after-free example:

```C
#include <stdlib.h>
#include <stdio.h>

// memory leak with heap allocation
int main() {
    // Get some memory from the allocator
    char* string = (char*) calloc(3, 1);
    string[0] = 'h';
    string[1] = 'i';

    printf("%s\n", string);

    // Don't bother to release the memory
}
```

Leaks aren't a memory-safety issue. Leaks just waste resources which can
seriously impact performance, or even cause a crash. Crashing is obviously not
good, so leaks should be avoided if possible. That said, leaks can be benign or
even desirable under the right circumstances. For instance, our example of a
leak is actually totally fine. Operating systems reclaim a process' memory on
exit anyway, so fiddling with the allocator is just slowing down the program's
execution for no good reason.

Most languages handle memory leaks with garbage collection. C++ primarily
handles memory leaks with destructors. C doesn't provide anything for avoiding
memory leaks. Regardless, no strategy is perfect because properly eliminating
leaks may require semantic understanding of how an application works. For
instance, none of the strategies mentioned can deal with forgetting to remove
unused values from a collection. Even ignoring these "undetectable" cases,
these strategies can also fail to properly collect truly unreachable memory
due to implementation details.

Memory leaks generalize to the leaking of basically any other resource such
as threads, file descriptors, or connections. Arguably, leaks are just a special
case of forgetting to do any final step at all. Garbage collection does nothing
for these errors, while destructors work just as well for them all.

Leaks are a sufficiently special case that we'll be skipping over them for
the bulk of this thesis. For now we'll only focus on the errors that can lead
to programs behaving incorrectly, instead of just poorly.




# Trust

We believe that the three memory-safety errors we described in the previous
section, and many more like them, all boil down to a single issue: data trust.
All programs require or expect data to have certain properties. This trust
is so pervasive that it's easy to forget that we're even making assumptions about
how data will behave. This trust has many aspects:




First, there is the *property* of the data that is trusted. The simplest form of
trust is trusting that certain values don't occur: booleans are either `true`
or `false`, but never `FileNotFound`. This kind of property is generally quite
manageable because it's easy to verify on demand.

The more complex form of property is trusting that separate pieces of data agree.
This is the kind of property that we see in our memory-safety errors. Indices need
to agree with the length of the array, the allocator needs to agree that
dereferenced pointers are allocated, and iterators need to agree with the collection
they iterate. This is the kind of trust we will be focusing on for the bulk of
this work.

Although we won't be exploring this, trust may also have a probabilistic nature.
One may expect that inputs are usually small or mostly duplicates.




Second, there is the *who* to trust with data. For most applications, it's pretty
reasonable to design an interface that assumes that the language, hardware, and
operating system are well-behaved. Of course, bugs in any of these systems
may necessitate workarounds, but we don't consider this aspect to be particularly
interesting. At some limit, these systems just work the way they work, and any
oddities can be regarded as a nasty corner-case to be documented.

The aspect of who to trust that we consider really interesting is within the
boundary of userland. Within a single program, functions need to decide whether
to trust other functions. It's fairly reasonable to trust a single concrete
function to be well-behaved. For instance, if one wishes to invoke a print
function that claims to only read its inputs, it's reasonable to rely on that
fact. We consider it reasonable to extend our trust here because it's being done
in a *closed* manner. That is, it's in principle possible to test or otherwise
verify that the print function doesn't mutate its input, especially if the
source is available.

The problematic case is when we need to extend our trust in an *open* manner. Public
functions can be called by arbitrary code, and as such need to worry about trusting
their caller. Do we trust the caller to pass us correct inputs? Do we trust the caller
to invoke us at the right time? Similarly, generic or higher-order functions need to
worry about trusting the arbitrary functions that they're given. If we were *given*
a printing function instead of getting to call some concrete
one, we then have to worry if that print function will uphold its promise not to mutate
the input.




Third, there is the *consequences* of the trust; what happens if trust
is violated? Consequences for an application can range from marginal to catastrophic;
it could perform slightly worse, produce nonsensical output, crash, delete the
production database, or compromise the system it's running on.
The consequences of an assumption can easily shape whether that assumption is
made at all. Certainly, leaving the system vulnerable is not something to be
taken lightly.




Fourth and finally, there is the *justification* of the trust. At one extreme, one may simply
blindly trust the data. Indexing is unchecked; pointers are assumed to be
allocated; and booleans are assumed to be true or false.

At the other extreme, one can statically guarantee that data is correct. Static
type checking can help ensure that a boolean doesn't contain FileNotFound,
control flow analysis can determine if a pointer is used after it's freed, and
normalized databases ensure that there is a single source of truth for each fact.

Somewhere in between these two extremes, one can *validate* or *correct* data
at runtime. Indexes may be checked against an array's length; inputs may
be escaped; and iterators can check that their collection hasn't been modified.

We respectively call these three approaches *naivety*, *paranoia*, and *suspicion*.
As we will see, they each have their own strengths and weaknesses that makes them appropriate
for different tasks. As such, basically every piece of software relies on a combination
of these strategies to strike a balance between the competing demands of control, safety,
and ergonomics. That said, some systems clearly favour some strategies more than others.



## Naivety

A naive interface isn't a fundamentally bad interface. It's just one that trusts
that the world is great and everyone is well-behaved. Providing a naive interface
is a bit like giving everyone you meet a loaded gun and trusting that they use
it wisely. If everyone *is* well-behaved, then everything goes great. Otherwise,
someone might lose a leg.

First and foremost, a naive interface
is simply the easiest to *implement*. The implementor doesn't need to concern
themselves with corner cases because they are simply assumed to not occur. This
in turn gives significant control to the user of the interface, because they don't
need to worry about the interface checking or mangling inputs. It's up to the user
to figure out how correct usage is ensured. This control is the greatest strength
of naivety.

For similar reasons, naive interfaces are also in principle ergonomic to work
with. In particular one is allowed to try to use the interface in whatever
manner they please. This enables programs to be transformed in a more continuous
manner. Intermediate designs may be incorrect in various ways, but if one is
only interested in exploring a certain aspect of the program that doesn't depend
on the incorrect parts, they are free to do so.

The uncontested champion of this approach is C. In particular, its notion of
*Undefined Behaviour* is exactly naivety. C programs are expected to uphold
several non-trivial properties, and the C standard simply declares that if those
properties *don't* hold, the program is *undefined*. This naivety can be found in
relatively small and local details like unchecked indexing, as well as massive
and pervasive ones like manual memory management.

Undefined Behaviour is the most demonstrates the extreme drawback of naive
interfaces. Breaking C's trust has dire consequences, as the compiler is free to misoptimize the
program in arbitrary ways, leading to memory corruption bugs and high severity
vulnerabilities. This is far from an academic concern; exploits deriving from
C's pervasive unsafety are bountiful. Modern compilers try to give
a helping hand with debug assertions and static analysis, but blind trust is
evidently too deeply ingrained into C. Programs written in languages like C
continue to be exploited, and no end to this is in sight.

If the consequences of misuse are high or the contracts that must be upheld are
too onerous, the ergonomic benefits of naive interfaces can be undermined.
Having to be always vigilant against incorrect usage can be mentally exhausting.
The problems that result from misusing a naive interface can also be cryptic and
difficult to debug, due to the fact that they don't tend to fail fast, but instead
silently corrupt the system.

That said, the control that C's trusting design provides is highly coveted.
Operating systems, web browsers, game engines, and other widely used pieces of
software continue to be primarily developed in C(++) because of the perceived
benefits of this control. Performance is perhaps the most well-understood benefit
of control, but it can also be necessary for correctness in the case of hardware
interfaces. Languages without this control are simply irrelevant for many projects.





## Paranoia

Paranoid designs represent a distrust so deep that one believes things must be
taken away so as to eliminate a problem *a priori*. Where the naive would give
everyone a loaded gun, the paranoid are so concerned with people getting shot
that they would try to make it impossible by eliminating bullets, guns, or even
people.

There are two major families of paranoid practices: omissions and static analysis.

Omissions represent pieces of functionality that could have been provided or
used, but were deemed too error-prone. The much-maligned `goto` is perhaps
the most obvious instance of a paranoid omission, but it's not the most
interesting. The most interesting omission is the ability to manually free memory,
which is the omission that all garbage collected languages effectively make.
Some less popular examples include always-nullable pointers (Haskell, Swift, Rust),
parallelism (JavaScript), and side-effects (pure functional programming).

Static analysis consists of verifying a program has certain properties at
compile-time. Static typing is the most well-accepted of these practices,
requiring every piece of data in the program to have a statically known type.
Various static lints for dubious behaviours also fall into this category,
including code style checks. This analysis also includes more exotic systems
like dependent-typing, which expresses requirements on runtime values (such as
`x < y`) at the type level.

The primary benefit of paranoid practices is maximum safety. Ideally, a paranoid
solution doesn't just handle a problem, it *eliminates* that problem. For
instance, taking away memory freeing completely eliminates the use-after-free,
because there is *no* "after free" (garbage collection being "only" an
optimization). Similarly, a lack of parallelism eliminates data races, because
it's impossible to race. Lints may completely eliminate specific mistakes, or
simply reduce their probability by catching the common or obvious instances.
Dependent typing can eliminate indexing out of bounds, by statically proving
that all indices are in bounds.

The cost of this safety is control. Paranoid practices point to the pervasive
problems that control leads to, and declare that this is why we can't have nice
things. It's worth noting that this loss of control does not necessarily imply a
loss in performance. In fact, quite the opposite can be true: an optimizing
compiler can use the fact that certain things are impossible to produce more
efficient programs.

That said, paranoid practices *do* generally take away a programmer's ability to
directly construct an optimized implementation. One must instead carefully craft
their program so that it happens to be optimized in the desired manner. This
leaves the programmer dependent on the compiler to understand how to produce the
desired idiom, and may require significant annotations to convince it that this
is desirable. In some cases, this means that the desired output is simply
impossible.

The ergonomic impact of paranoid practices is a tricky subject. For the most
part, paranoid practices err on the side of producing false negatives -- better to
eliminate some good programs than allow bad programs to exist! This can lead to
frustration if one wishes to produce a program they believe to be a false
negative.

Omissions are generally much more well-accepted in this regard, particularly
when an alternative is provided that handles common cases. The
absence of manual free is quite popular because freeing memory is purely annoying
book-keeping. Freeing memory has no inherent semantic value, it's just necessary
to avoid exhausting system resources. The fact that garbage collection just
magically frees memory for you is pretty popular, as evidenced by its dominance
of the programming language landscape (C and C++ being the notable defectors).
However some omissions can be too large to bear. Few systems are designed in
a pure-functional manner.

Static analysis is much more maligned, as the developers of
[coverity][] found. It's easy to forgive an omission, particularly if one isn't
even aware that an omission occurred (how many programmers are even aware of
`goto` these days?). Static analysis, on the other hand, is active and in the programmer's face.
It continuously nags the programmer to do a better job, or even prevents the
program from running. Static typing, one of the less controversial
strategies, is rejected by many popular languages (JavaScript, Python, Ruby).
Meanwhile, dependent types struggle to find any mainstream usage at all. These practices
can also harm the ability to continuously transform a program, forcing the
programmer to prove that *everything* is correct in order to test *anything*.

Regardless, embracing paranoia *can* be liberating. Once a paranoid
practice is in place, one never needs to worry about the problems it addresses
again. Once you start collecting your own rainwater, why worry what's being put
in the water supply?




## Suspicion

Finally we have the position of compromise: the suspicious practices. A suspicious
design often looks and acts a lot like a trusting design, but with one caveat: it
actually checks at runtime. The suspicious stance is that some baseline level of
safety is important, but categorically eliminating an error with a paranoid practice
is impractical. The suspicious might give everyone guns, but make them explode whenever
a HumanPointerException is detected.

Suspicious practices can skew to be implicit or explicit, in an
attempt to fine-tune the tradeoffs.

In languages where pointers are nullable by default, it's common for all dereferences
to silently and implicitly check for `null`. This may cause the program to completely
crash or trigger unwinding (an "exception" in many languages). This allows the programmer
to write the program in a trusting way without worrying about the associated danger.

Other interfaces may require the author to explicitly acknowledge invalid cases.
For instance, an API may only provide access to its data through callbacks which it
invokes when the data is specifically correct or incorrect. This approach is often
more general, as it can be wrapped to provide the implicit form. Compared to
implicit checks, explicit checks give more control to the user and can improve the
clarity of code by making failure conditions more clear. But this comes at
a significant ergonomic cost; imagine if every pointer dereference in Java
required an error callback!

Regardless of the approach, suspicious practices are a decent compromise. For
many problems the suspicious solution is much easier to implement, work with,
and understand than the paranoid solution. Array indexing is perhaps the best
example of this. It's incredibly simple to have array indexing unconditionally
check the input against the length of the array. Meanwhile, the paranoid
solution to this problem requires an integer theorem solver and may require
significant programmer annotations for complex access patterns. That said,
paranoid solutions can also be simpler. Why check every dereference for
null, when one can simply not let pointers be null in the first place?

One significant drawback of suspicious practices, particularly of the implicit
variety, is that they do little for program *correctness*. They just make sure
that the program doesn't do arbitrary unpredictable things with bad data, usually by
reliably crashing the program. This can be great for detecting, reproducing,
and fixing bugs, but a crash is still a crash to the end user. This can be
especially problematic for critical systems, where a crash is essentially a
critical vulnerability.

Suspicious solutions also often have the worst-in-class performance properties
of the three solutions. Trusting solutions let the programmer do whatever they
please while still aggressively optimizing. Paranoid solutions give the
compiler and programmer rich information to optimize the program with.
But suspicious solution gets to assume little, and must bloat up
the program with runtime checks which further inhibit other optimizations.
That said, a good optimizing compiler can completely eliminate this gap in
some cases. Bounds checks in particular can be completely eliminated in common cases.










# Ownership

Rust tries to be a practical language. It understands that each perspective has
advantages and drawbacks, and tries to pick the best tool for each job. From each
perspective, Rust takes one key insight. From the naive perspective, we embrace
that control is incredibly important. Rust wants to be used in all the places where
C and C++ are used today, and being able to manually manage memory is a critical
aspect of that. From the paranoid perspective, we embrace that completely
eliminating errors is great. Humans are fallible and get tired, but a good compiler
never rests and always has our back. From the suspicious perspective, we embrace
that compromises must be made for ergonomics and safety.

Part of Rust's solution is then simply taking our favourite solutions for
each specific problem: static types, runtime bounds checks, no nulls, wrapping
arithmetic, and so on. However Rust has one very large holistic solution to
many problems, and it's what separates it from most other languages: ownership.
The ownership model has two major aspects: controlling where and when data lives;
and controlling where and when mutation can occur. These aspects are governed by
two major features: affine types and regions.





## Affine Types

At a base level, Rust manages data ownership with an *affine type system*. The
literature often describes affine types as being usable *at most once*, but from
Rust's perspective affine typing primarily means values are *uniquely owned*.
To C++ developers, affine typing can be understood as a stricter version of
*move semantics*.

If a variable stores a collection, passing it to a function by-value or
assigning it to another variable transfers ownership of the value to the new
location. The new location gains access to the value, and the old location loses
access. Whoever owns the value knows that it's the only location
in existence that can possibly talk about the contents of the collection.
This allows the owner of the collection to soundly *trust* the
collection. Any properties it observes and wishes to rely on will not be changed
by some other piece of code without its permission. Perhaps more importantly,
the owner of the collection knows that it can do whatever it pleases with the
collection without interfering with anyone else.

A simple example:

```rust
fn main() {
    // A growable array
    let data = Vec::new();

    // transfer ownership of `data` to `data2`
    let data2 = data;
    // `data` is now statically inaccessible, and logically uninitialized

    // transfer ownership of `data2` to `consume`
    consume(data2)
    // `data2` is now statically inaccessible, and logically uninitialized
}

fn consume(mut data3: Vec<u32>) {
    // Mutating the collection is known to be safe, because `data3` knows
    // it's the only one who can access it.
    data3.push(1);
}
```

The greatest of these rights is destruction: when a variable goes out of scope,
it destroys its value forever. This can mean simply forgetting the value,
or it can mean executing the type's destructor. In the case of a collection,
this would presumably recursively destroy all contained values, and free all of
its allocations.

Affine types are primarily useful for eliminating the *use-after* family of bugs.
If only one location ever has access to a value, and a value is only invalidated
when that one location disappears, then it's trivially true that one cannot use
an invalidated value. For this reason, the most obvious applications of affine
typing are with various forms of transient resources: threads, connections,
files, allocations, and so on.

However it turns out that a surprising number of problems can be reduced to a
use-after problem. For instance, many APIs require some sequence of steps to
be executed in a certain order. This can be encoded quite easily using affine
types. Functions can produce a "proof of work" by returning a type that only
they have permission to produce. Similarly, functions can *require* a proof
of work by consuming a special type:

```rust
fn first() -> First;
fn second(First) -> Second;
fn third(Second) -> Third;
fn alternative(First) -> Alternative;
```

We can therefore use affine types to model valid control flow and statically
ensure correct usage. *[Session types][]* are the logical extreme of this
technique, where programs effectively "write themselves" due to their type
constraints.

It should be noted that affine typing isn't mandatory in Rust. For many types,
like booleans and integers, unique ownership doesn't make sense or isn't
important. Such types can opt into *copy* semantics. Copy types behave like any
other value with one simple caveat: when they're moved, the old copy of the
value is still valid.

Copy semantics can have surprising consequences though. For instance, it may be
reasonable for a random number generator to be copyable,  as their internal
state is generally just some integers. It then becomes possible to
*accidentally* copy the generator, causing the same number to be yielded
repeatedly. For this reason, some types which *could* be copied safely don't opt
into copy semantics. In this case, affine typing is used as a lint against what
is likely, but not necessarily, a mistake.





## Borrows and Regions

Affine types are all fine and good for some problems, but if that's all Rust had,
it would be a huge pain in the neck. In particular, it's very common to want
to *borrow* a value. In the case of a unique borrow, affine types can encode
this fine: you simply pass the borrowed value in, and then return it back.

This is, at best, just annoying to do. Borrows must be "threaded" throughout
such an API explicitly in both the types and code:

```rust
struct Data { secret: u32 }

fn main() {
    let mut data = Data { secret: 0 }
    data = mutate(data);
    data = mutate(data);
    data = mutate(data);
}

fn mutate(mut data: Data) -> Data {
    data.secret += 1;
    return data;
}
```

Affine types *really* hit a wall when data wants to be *shared*. If
several pieces of code wish to concurrently read some data, we have a serious
issue. One solution is to simply *copy* the data to all the consumers. Each
has their own unique copy to work with, and everyone's happy.

However, even if we're ignoring the performance aspect of this strategy (which
is non-trivial), it may simply not make sense. If the underlying resource to
share is truly affine, then there may be *no* way to copy the data in a
semantic-preserving way. For instance, one cannot just blindly copy a file
handle, as each holder of the handle could then close it while the others are
trying to use it.

At the end of the day, having only values everywhere is just dang *impractical*.
Rust is a practical language, so it takes a tried and true solution: pointers! Unfortunately,
pointers make everything more complicated and difficult. Affine types "solved"
use-after errors for us, but pointers bring them back and make them *far* worse.
The fact that data has been moved or destroyed says nothing of the state of
pointers to it. As C has demonstrated since its inception, pointers are all too
happy to let us view data that might be destroyed or otherwise invalid.

Garbage collection solves this problem for allocations, but does nothing to
prevent trying to use an otherwise invalidated value, such as a closed file.
Rust's solution to this problem is Cyclone's most significant contribution to
the language: [regions][cyclone-regions].

Like affine types, regions are something well established in both theory and
implementation, but with little mainstream usage. Although Rust primarily cribs
them from Cyclone, they were first [described by Tofte and Talpin][tofte-regions]
and used in an implementation of ML. That said, Cyclone's version of regions
is most immediately recognizable to a Rust programmer.

The idea of a region system is that pointers are associated with the region of
the program that they're valid for, and the compiler ensures that pointers don't
escape their region. This is done entirely at compile time, and has no runtime
component.

For Rust, these regions correspond to lexical scopes, which are roughly speaking
pairs of matching braces.The restriction to lexical scopes is not fundamental,
and was simply easier to implement for the 1.0 release. It is however sufficient
for most purposes. Rust calls these regions *lifetimes*.

At a base level, all a region system does is statically track what pointers are
outstanding during any given piece of code. By combining this information with
other static analysis it's possible to completely eliminate several classes of error
that are traditionally relegated to garbage collection. Region analysis allows us
to statically identify when a value is moved or destroyed while being pointed to,
and produce an error to that effect:

```rust
fn main() {
    // Gets a dangling pointer
    let data = compute_it(&0);
    println!("{}", data);
}

fn compute_it(input: &u32) -> &u32 {
    let data = input + 1;
    // Returning a pointer to a local variable
    return &data;
}
```

```text
<anon>:11:13: 11:17 error: `data` does not live long enough
<anon>:11     return &data;
                      ^~~~
<anon>:8:36: 12:2 note: reference must be valid for the anonymous lifetime #1 defined on the block at 8:35...
<anon>: 8 fn compute_it(input: &u32) -> &u32 {
<anon>: 9     let data = input + 1;
<anon>:10     // Returning a pointer to a local variable
<anon>:11     return &data;
<anon>:12 }
<anon>:9:26: 12:2 note: ...but borrowed value is only valid for the block suffix following statement 0 at 9:25
<anon>: 9     let data = input + 1;
<anon>:10     // Returning a pointer to a local variable
<anon>:11     return &data;
<anon>:12 }
```

On its own, this is pretty great: no dangling pointers without the need for
garbage collection! However when combined with an affine type system
we get something even more powerful than garbage collection. For instance, if
you close a file in a garbage collected language, there is nothing to prevent
old pointers to the file from continuing to work with it. One must guard for
this at runtime. In Rust, this is simply not a concern:
it's statically impossible. Closing the file destroys it, and that means all
pointers must be gone.

Unfortunately, this doesn't solve problems like iterator invalidation. When an
iterator is invalidated, the collection it was pointing to wasn't *destroyed*,
it was just changed.

The most extreme solution is to simply forbid internal pointers. Only allow
pointers to borrow variables on the stack, and everything else has to be copied
out. Then we never have to worry about pointers being invalidated. Unfortunately,
this would be a very limiting system. It would make composition of affine types useless,
because you could never access the components without destroying the aggregate.
It also doesn't really solve the problem the way we wanted. Most iterators we'd
be interested in providing would become inexpressible under this model. For
instance, one couldn't yield interior pointers from an iterator. Depending on
the details, any kind of tree iterator may be completely impractical.

Another extreme solution would be to forbid mutation of data. Mutations can be emulated
by creating a new object with the necessary changes, so this is in principle
possible. However this suffers from similar issues as borrow threading: it's
really annoying. It would also be incredibly difficult to obtain the same
control as C(++) under this model.

Yet another way is to treat all pointers into the array as pointers *to*
the array, and simply forbidding mutation *through* pointers. All mutating operations
could require by-value (and therefore unique) access, which could be done with borrow-threading.
This is unfortunate because we were trying to avoid borrow-threading by introducing
pointers in the first place. But hey, at least we could share data immutably,
which is a definite win.

Rust basically takes this last approach, but in order to avoid the annoying pain of
threading borrows, it includes two different *kinds* of pointer:
*mutable references* and *shared references* denoted `&mut` and `&`
respectively. Shared references are exactly as we described: they can be
freely aliased, but only allow you to read the data they point to. Mutable
references on the other hand must be unique, but enable mutation of the data
they point to. This means that taking a mutable reference to some data is like moving
it, but then having the compiler automatically insert all the boiler-plate
to move it back into place when the mutable reference is gone (the
compiler does not actually move the data around when you take a mutable
reference).




## Mutable XOR Shared

This is Rust's most critical perspective on ownership: mutation is mutually
exclusive with sharing. In order to get the most out of this perspective, Rust
doesn't allow mutability to be declared at the type level. That is, a struct's
field cannot be declared to be constant. Instead, the mutability of a value is
*inherited* from how it's accessed: as long as you have something by-value or
by-mutable-reference, you can mutate it.

This stands in contrast to the perspective that mutation is something to be
avoided completely. It's well-known that mutation can cause problems, as we've
seen. This has lead some to conclude that mutation should be avoided as much
as possible. Never mutating anything does indeed satisfy Rust's requirement
that sharing and mutating be exclusive, but in a vacuous way (mutating never
occurs). Rust takes a more permissive stance: mutate all you want as long
as you're not sharing. It is our belief that this eliminates most of the
problems that mutation causes in practice.

In particular, this statically eliminates iterator invalidation. For
instance, consider the following program:

```rust
fn main() {
    let mut data = vec![1, 2, 3, 4, 5, 6];
    for x in &data {
        data.push(2 * x);
    }
}
```

What exactly the programmer's intent was here was unclear, and what exactly
will happen if this were allowed to compile is even more unclear.
Thankfully, in Rust we don't *need* to wonder what the programmer meant or
what will happen when this is run, because it doesn't compile:

```text
<anon>:4:9: 4:13 error: cannot borrow `data` as mutable because it is also borrowed as immutable
<anon>:4         data.push(2 * x);
                 ^~~~
<anon>:3:15: 3:19 note: previous borrow of `data` occurs here; the immutable borrow prevents subsequent moves or mutable borrows of `data` until the borrow ends
<anon>:3     for x in &data {
                       ^~~~
<anon>:5:6: 5:6 note: previous borrow ends here
<anon>:3     for x in &data {
<anon>:4         data.push(2 * x);
<anon>:5     }
             ^
```

This strategy also nicely generalizes to a concurrent context. A data race is
defined to occur when two threads access a piece of data in an unsynchronized
way, and one is writing. This is exactly aliasing and mutation, which is
forbidden by Rust's scheme. As such, everything in Rust is thread-safe by default.

Of course, perfectly good concurrent algorithms and data structures are rife with aliasing and
mutability. Mutexes exist *precisely* to enable aliasing and mutation in a
controlled manner. As a result, although inherited mutability is the default way to do things in
Rust, it is not the only way. A few key types provide *interior mutability*,
which enables their data to be mutated through shared references as long as some
runtime mechanism ensures that mutable references aren't aliased. The most
obvious example of this is exactly the standard library's Mutex type, which
allows an `&Mutex<T>` to become an `&mut T` by acquiring its lock. This is in
turn made sound by affinity and the borrow checker ensuring the







# Unsafe Rust

Most languages are considered memory-safe. However with few exceptions, this
isn't actually true. In fact, basically *every* language has unsafe bits that
make the language totally unsound. The most fundamental of these is quite
simple: talking to C. C is the lingua-franca of the programming world. All
major operating systems and many major libraries primarily expose a C interface.
Any language that wants to integrate with these systems must therefore learn
how to talk to C. Because C is *definitely* unsafe and can do just about anything
to your program, these languages then become transitively unsafe.

Rust is no different, but it embraces this reality a little more than most
other languages. Rust is actually *two* languages: Safe Rust, and Unsafe Rust.
Safe Rust is the Rust we have been focusing on for the most part. It
is intended to be completely safe with one exception: it can talk to
Unsafe Rust. Unsafe Rust, on the other hand, is definitely not a safe language.
In addition to being able to talk to C (like any safe language), it enables the
programmer to work with several constructs that would be easily unsound for
Safe Rust. Most notably, Unsafe Rust includes raw C-like pointers which are
nullable and untracked.

At first glance, Unsafe Rust appears to completely undermine Rust's claims about
safety, but we argue that it in fact *improves* its safety story. In most safe
languages, if one needs to do something very low level (for performance, control,
or any other reason) the general solution to this is "use C". This has several
downsides.

First, there's a cognitive overhead. Such an application now has
its logic spread across two completely different languages with different
semantics, runtimes, and behaviors. If the safe language is what the development
team primarily works in, it's unlikely that a significant percentage of the team
is qualified to actively maintain the C components. Second, it incurs non-trivial
runtime overhead. Data must often be reformatted at the language boundary, and
this boundary is usually an opaque box for either language's optimizer.
Finally, falling back to C is simply a *huge* jump in unsafety, from "totally
safe" to "pervasively unsafe".

Unsafe Rust largely avoids these issues with one simple fact:
it's just a superset of Safe Rust. Lifetimes, Affine Types, and everything else
that helps you write good Rust programs are still working exactly as before.
You're just allowed to do a few extra things that are unsafe. As a result,
there's no unnecessary runtime or semantic overhead for using Unsafe Rust.

Of course one *does* need to understand how to manually uphold Safe Rust's
various guarantees when using Unsafe Rust's extra parts, and this isn't trivial.
However this is still a better situation than using C, because the unsafety is
generally much more modular. For instance, if you use Unsafe Rust to index into
an array in an unchecked manner, you don't suddenly need to worry about the
array being null, dangling, or containing uninitialized memory. All you need to
worry about is if the index is actually in bounds. You know everything else is
still normal.

In addition, Unsafe Rust doesn't require any kind of complicated foreign
function interface. It can be written inline with Safe Rust on demand. Rust's
only requirement is that you write the word `unsafe` *somewhere* to indicate
that you understand that what you're doing is unsafe. Since unsafety is
explicitly denoted in this manner, it also enables it to be detected and linted
against if desired.

Rust's standard library (which is written entirely in Rust) makes copious use of
Unsafe Rust internally. Most fundamentally, Unsafe Rust is necessary to provide
various operating system APIs because those are written in C, and only Unsafe
Rust can talk to C. However Unsafe Rust is also used in various places to
implement core abstractions like mutexes and growable arrays.

It's important to note that the fact that these APIs use unsafe code is entirely
an implementation detail to those using the standard library. All the unsafety
is wrapped up in *safe abstractions*. These abstractions serve two masters: the
consumer of the API, and the producer of the API. The benefit to consumers of an
API is fairly straight-forward: they can rest easy knowing that if something
terrible happens, it wasn't their fault. For producers of the API, these safe
abstractions mark a clear boundary for the unsafety they need to worry about.

Unsafe code can be quite difficult because it often relies on stateful
invariants. For instance, the capacity of a growable array is a piece of state
that unsafe code must trust. However within the array's privacy boundary, this
state can be arbitrarily manipulated by anyone. The abstraction boundary is
often exactly where privacy kicks in, preventing consumers of the API from doing
arbitrarily bad things to the state unsafe code relies on.

This thesis focuses primarily on these safe abstractions. A good safe abstraction
must have many properties:

* Safety: Using the abstraction inappropriately cannot violate Rust's safety guarantees.
* Efficiency: Ideally, an abstraction is *zero cost*, meaning it is as efficient
  at the task it is designed to solve as an unabstracted solution (with a decent
  optimizing compiler).
* Usability: A good abstraction should be more convenient and easy to understand than
  the code it's wrapping.

It would be *excellent* if the implementation was also completely safe, but we
do not consider this a critical requirement.

It should be noted that Rust's reliance on safe abstractions is, in some sense,
unfortunate. For one, it makes reasoning about the performance characteristics
of a program much more difficult, as it relies on a sufficiently
smart compiler to tear away these abstractions. This in turn means Rust's unoptimized
performance in a rather atrocious state. It's not uncommon for a newcomer to
the language to express shock that a Rust program is several times slower than
an equivalent Python program, only to learn that enabling optimizations makes
the Rust program several times *faster* than the Python program.
However it is our opinion that this is simply fundamental to providing a
programming environment that is safe, efficient, and usable.








# Designing APIs for Trust

It has been our experience that almost everything you want to express at a high level
can be safely, efficiently, and usably expressed in an ownership-oriented system.
However this does *not* mean that you can express it however you please!
In order to achieve all of these goals, the API itself must be designed in
terms of data trust. If the API isn't designed with trust and ownership in mind,
safety, efficiency, or usability will likely be compromised.




## Indexing

Let's return to the problem of indexing out of bounds. Arrays are overwhelmingly
the most common and important data structure. Basically every
program will do some array processing -- even *hello world* is just copying an
array of bytes to stdio. Array processing is so pervasive that Rust provides no
less than *four* different ways to index into an array, corresponding to the
trust strategies: naive, paranoid, implicitly suspicious, and
explicitly suspicious.

First and foremost, Rust provides the two most popular interfaces: completely
unchecked indexing (via Unsafe Rust), and implicitly checked indexing (which
unwinds the program if it fails). Nothing particularly surprising or
novel there.

Slightly more interesting is how Rust provides an explicitly checked option.
Explicit checking is most commonly done through the Option and Result types
in Rust. If an operation can fail, it will return one of these types.
These types are simple tagged unions, which means they can contain different
types at runtime. `Option<T>` can be `Some(T)` or `None`, while `Result<T, E>`
can be `Ok(T)` or `Err(E)`. By owning the data they wrap, these types can control
how it's accessed. Both of them provide a multitude of ways to access their
contents in an explicitly checked way.

So if we want to explicitly handle indexing failing, we can do any of the
following:

```rust
// Exhaustively match on the possible choices
match array.get(index) {
    Some(elem) => println!("Elem: {}", elem),
    None       => println!("Nothing"),
}

// Only handle one pattern
if let Some(elem) = array.get(index) {
    println!("Elem: {}", elem);
}

// Execute a callback if the value is Some
array.get(index).map(|elem| {
    println!("Elem: {}", elem);
});

// ... And more
```

It's worth noting checked indexing is surprisingly performant here.
First off, these bounds checks are by definition trivially predictable in a
correct program. So the overhead at the hardware level is quite small. That said,
having to do the checks at all is the worst-case. A good optimizing compiler
(like LLVM) can optimize away bounds checks in many "obviously correct" cases.
For instance, the following code doesn't actually perform any bounds checks
when optimized, because LLVM can see that the way the indices are generated
trivially satisfies the bounds checking.

```rust
let mut x = 0;
for i in 0 .. arr.len() {
    // implicit checked indexing
    x += arr[i];
}
```

Indeed, if you can convince LLVM to not completely inline and constant-fold
this code away, it will even successfully vectorize the loop!

However compiler optimizations are brittle things that can break under even
seemingly trivial transformations. For instance, changing this code to simply
iterate over the array *backwards* completely broke LLVM's analysis and produced
naive code that adds the integers one at a time with bounds checking. This is
perhaps the most serious cost of bounds checks: inhibiting other optimizations.

If we really care about avoiding this cost, we can't just rely on the optimizer
to magically figure out what we're doing, we need to actually not do bounds
checking. We can use the unsafe unchecked indexing, but we'd rather not resort
to unsafe code unless totally necessary. What we really want here is the final
solution: the paranoid one.

This code is hard to optimize safely
because we've pushed too much of the problem at hand to the user of the array.
They need to figure out how to generate the access pattern, and we in turn can't
trust it. If the *array* handles generating the access pattern *and*
acquiring the elements, then all the bounds checks can be eliminated at the
source level in a way that's safe to the end-user. This is handled by a tried
and true approach: iterators.

```rust
let mut sum = 0;
for x in arr.iter() {
    sum += *x;
}
```

This produces the same optimized code as the original indexing-based solution,
but more importantly, it's more robust to transformations. Iterating
backwards now also produces vectorized unchecked code, because the optimizer
has less to prove about the program's behaviour. As an added bonus, client code
ends up simplified as well, as all the error-prone iteration boiler plate has
been eliminated.

Of course, this doesn't come for free: iterators are effectively special-casing
certain access patterns at the burden of the interface's implementor. In the
case of iterators, this burden is well justified. Linear iteration
is incredibly common, and therefore well worth the specialization. But if the
user wants to binary search an array without bounds checks, iterators do them no
good.

This is why Rust also provides the raw unchecked indexing API. If users have a
special case and really need to optimize it to death, they can drop down to
the raw API and regain full control. In the case of arrays, the raw API is
trivial to provide and obvious, so there's little worry of the maintenance burden
or unnecessarily exposing implementation details. Unfortunately, this isn't true for all
interfaces (what's the raw API for searching an ordered map?).






## Hacking Dependent Types onto Rust

Given the array iteration example, one might wonder if it's sufficient for the
array to simply provide the indices. This would be a more composable API with
a reduced implementation burden. Perhaps this API could be used something like this:

```rust
let mut sum = 0;
for i in arr.indices() {
    sum += arr[i];
}
```

Unfortunately, this doesn't immediately get us anywhere. This is no different
than the original example which produced its own iteration sequence. As soon
as the array loses control of the yielded indices, they are *tainted* and all
trust is lost. One may consider wrapping the integers in a new type that doesn't
expose the values to anyone but the array, preventing them from being
tampered with, but this is still insufficient unless the *origin* of
these values can be verified. Given two arrays, it mustn't be possible to index
one using the indices of the other:

```rust
let mut sum = 0;
for i in arr1.indices() {
    // index arr2 using arr1's trusted indices
    sum += arr2[i];
}
```

This is a problem most static type systems generally struggle to model, because
they don't provide tools to talk about the origin or destination of a particular
instance of a type. In addition, even if we could prevent this, we would have to
deal with the problem of temporal validity. The indices into an array are only
valid as long as the array's length doesn't change:

```rust
let i = arr.indices().next().unwrap();
arr.pop();
// index arr with an outdated index
let x = arr[i];
```

By pure accident, Rust provides enough tools to solve
this problem. It turns out that lifetimes in conjunction with some other features
are sufficient to construct a limited form of dependent typing. We won't lie:
this is an ugly hack, and we don't expect anyone to use it seriously.
Still, it demonstrates the power of the ownership system.

In order to encode sound unchecked indexing, we need a way for types to talk about
particular instances of other types. In this case, we specifically need a way
to talk about the relationship between a particular array, and the indices it's
produced. Rust's lifetime system, it turns out, gives us exactly that. Every
instance of a value that contains a lifetime (e.g. a pointer) is referring to
some particular region of code. Further, code can require that two lifetimes
satisfy a particular relationship (typically, that one outlives the other).

The basic idea is then as follows: associate an array and its indices with
a particular region of code. Unchecked indexing then simply requires that the
input array and index are associated with the same region.
However care must be taken, as Rust was not designed to support this. In
particular, the borrow checker is a constraint solver that will attempt do
everything in its power to make code type-check. As such, if it sees
a constraint that two lifetimes must be equal, it may expand their scopes in
order to satisfy this constraint. Since we're trying to explicitly use equality
constraints to prevent certain programs from compiling, this puts us at odds
with the compiler.

In order to accomplish our goal, we need to construct a black box that the
borrow checker can't penetrate. This involves two steps: disabling lifetime variance,
and creating an inaccessible scope. Disabling variance is relatively straight
forward. Several generic types disable variance in order to keep Rust sound.
Getting into the details of this is fairly involved, so we will just
say we can wrap a pointer in the standard library's Cell type as follows:

```rust
struct Index<'id> {
    data: usize,
    _id: Cell<&'id u8>,
}
```

Of course we don't *actually* want to store a pointer at runtime, because we're
only interested in creating a lifetime for the compiler to work with. Needing to
signal that we contain a lifetime or type that we don't directly store is a
sufficiently common requirement in Unsafe Rust that the language provides a primitive
for exactly this: PhantomData. PhantomData tells the type system "pretend I
contain this", while not actually taking up any space at runtime.

```rust
// Synonym to avoid writing this out a lot
type Id<'id> = PhantomData<Cell<&'id u8>>;

struct Index<'id> {
    data: usize,
    _id: Id<'id>,
}
```

Now Rust believes it's unsound to freely resize the `'id` lifetime. However, as
written, there's nothing that specifies where this `'id` should come from. If
we're not careful, Rust could *still* unify these lifetimes if it notices
there's no actual constraints on them. Consider the following kind of program
we're trying to prevent:

```rust
let arr1: Array<'a> = ...;
let arr2: Array<'b> = ...;
let index: Index<'a> = arr1.get_index();

// This should fail to compile; trying to index Array<'b> with Index<'a>
let x = arr2[index];
```

If we don't constrain the lifetimes `'a` and `'b`, then the constraint solver
will see only the following system:

* `'a` and `'b` are invariant lifetimes
* indexing requires `'a = 'b`

Which has the obvious solution of `'a = 'b = anything`. We need to apply some
constraint to `'a` and `'b` to prevent Rust from unifying them. Within a single
function the compiler has perfect information and can't be tricked. However
Rust explicitly does not perform inter-procedural analysis, so we can apply
constraints with functions. In particular, Rust has to assume that the *input*
to a function is a fresh lifetime, and can only unify them if that function
provides constraints:

```rust
fn foo<'a, 'b>(x: &'a u8, y: &'b u8) {
    // cannot assume x has any relationship to y, since they
    // have their own lifetimes
}

fn bar<'a>(x: &'a u8, y: &'a u8) {
    // x has the same lifetime as y, since they share 'a
}
```

Therefore, for every fresh lifetime we wish to construct, we require a new
function call. We can do this in as ergonomically as possible (considering this
is a hack) by using closures:

```
fn main() {
    let arr1 = &[1, 2, 3, 4, 5];
    let arr2 = &[10, 20, 30];

    // Yuck! So much nesting!
    make_id(arr1, move |arr1| {
    make_id(arr2, move |arr2| {
        // Within this closure, Rust is forced to assume that the lifetimes
        // associated with arr1 and arr2 originate in their respective make_id
        // calls. As such, it is unable to unify them.

        // Iterate over arr1
        for i in arr1.indices() {
            // Will compile, no bounds checks
            println!("{}", arr1.get(i));

            // Won't compile
            println!("{}", arr2.get(i));
        }
    });
    });
}

/// An Invariant Lifetime
type Id<'id> = PhantomData<Cell<&'id u8>>;

/// A wrapper around an array that has a unique lifetime
struct Array<'arr, 'id> {
    array: &'arr [i32],
    _id: Id<'id>,
}

/// A trusted in-bounds index to an Array with the same lifetime
struct Index<'id> {
    idx: usize,
    _id: Id<'id>,
}

/// A trusted iterator of in-bounds indices into an Array
/// with the same lifetime
struct Indices<'id> {
    min: usize,
    max: usize,
    _id: Id<'id>,
}

/// Given a normal array, wrap it to have a unique lifetime
/// and pass it to the given function
pub fn make_id<'arr, F>(array: &'arr [i32], func: F)
    where F: for<'id> FnOnce(Array<'arr, 'id>),
{
    let arr = Array { array: array, _id: PhantomData };
    func(arr);
}

impl<'arr, 'id> Array<'arr, 'id> {
    /// Access the following index without bounds checking
    pub fn get(&self, idx: Index<'id>) -> &'arr i32 {
        unsafe { self.get_unchecked(idx.idx) }
    }

    /// Get an iterator over the indices of the array
    pub fn indices(&self) -> Indices<'id> {
        Indices { min: 0, max: self.array.len(), _id: PhantomData }
    }
}

impl<'id> Iterator for Indices<'id> {
    type Item = Index<'id>;
    pub fn next(&mut self) -> Option<Self::Item> {
        if self.min == self.max {
            None
        } else {
            self.min += 1;
            Some(Index { idx: self.min - 1, _id: PhantomData })
        }
    }
}
```

That's a *lot* of work to safely avoid bounds checks, and although there's
only a single line marked as `unsafe`, its soundness relies on a pretty deep
understanding of Rust. Any errors in the interface design could easily make
the whole thing unsound. So we *really* don't recommend doing this. Also, whenever
this interface catches an error, it produces nonsensical lifetime errors because
Rust has no idea what we're doing. That said, it does demonstrate our ability to
model particularly complex constraints.




# Limitations of Ownership

We've seen several problems that ownership allows us to cleanly model several
problems, preventing incorrect usage without runtime overhead. In particular,
ownership is very good at preventing the use-after and view-invalidation
classes of errors. This is because ownership's primary role is to prevent data
from being accessed at inappropriate times. However ownership is unable to
properly model the opposite problem: *requiring* data be accessed.

Perhaps the most famous class of errors that this covers is *leaks*. Leaks occur when
a program acquires resources but fails to release them when they're no longer
needed. Memory leaks are the most infamous, but one also easily leak file
descriptors, threads, connections, and more. Leaks are a particularly
pernicious bug because they generally don't immediately affect the behaviour
of a program. Leaks may be completely irrelevant, or even desirable, for
short-lived programs. However leaks may cause long-lived programs to mysteriously
crash at seemingly arbitrary times.

Leaks aren't well-modeled by ownership because they occur when a program *doesn't*
do something: freeing memory, closing a file, terminating a thread, and so on.
Unfortunately, the nature of leaks makes them much harder to define, and therefore
eliminate. Most would generally agree that completely forgetting about an
address in memory without freeing it is a leak. However simply holding onto a
value that will never again be used is arguably also a leak. In extreme cases,
simply failing to throttle usage may be regarded as a leak.

The classic leak is something that is fairly well-defined and approachable,
but the more advanced kinds of leak are something we consider impractical to
address, due to their reliance on arbitrary program semantics.

The ability to just drop a value on the ground and forget about it is an
explicit feature of affine types, which say values can be used *at most* once.
In order to encode that a value must be properly consumed, we need to be able
to express that a value must be used *exactly* once. Types with this property
are said to be *linear*.

A poor-man's linear-typing can be acquired with *destructors*. A value's destructor
is some code to execute when it goes out of scope. This effectively mandates that
values with destructors be used exactly once: the owner who decides to drop the
value on the ground is forced to invoke the value's destructor.

The most obvious limitation to this approach is that since destructors are implicitly invoked,
they cannot take any additional context. For instance, it may be desirable
to have a type that is allocated using a custom allocator, but does not store
a pointer to that allocator. The type therefore has insufficient information
to clean itself up, requiring the allocator be passed to it. A more robust linearity
system would allow us to encode this by requiring the destructor be explicitly invoked with
the allocator as an argument.

That said, destructors do a great job for many types. Collections and files
have a single "natural" final operation that requires no additional context.
Collections free their allocations and Files close their file descriptors.
Destructors also have the distinct advantage over more general linearity in that
they compose well with generic code. If some generic code wants to drop a value
on the ground, it can always do this knowing any linear requirements will be
satisfied by the destructor. Destructors provide a uniform interface with no
context required precisely *because* they aren't general.

Unfortunately, ensuring that code *does* execute is a bit of a nastier problem.
At the limit, hardware can fail and programs can abort. We just need to live
with that fact. For most resources this is actually fine; either the resources are
rendered irrelevant by the program ending, or the operating system will automatically
clean them all up itself.

However even accepting those circumstances, strict
linearity is a bit of a pain. In particular, it is desirable to be able to
create reference-counted cycles of types with destructors. If all references to
this cycle are lost, then it will still keep itself alive, leaking the destructors
themselves. Further, it is sometimes desirable to manually prevent a destructor
from running, particularly when decomposing it into its constituent parts. For
instance, one may wish to downgrade a pointer that knows it lives on the heap
to a raw pointer, perhaps to pass to a C API.

There are various solutions to this problem, but most languages that include
destructors (C++, Rust, D, C#, Java, ...) generally accept that sometimes
destructors (AKA finalizers) won't run. They're convenient and generally
reliable, but if one *really* needs something to happen, they can't always be
relied on. For Rust in particular, one can't pass a value with a destructor to
an arbitrary third-party, and rely on the destructor to ever be called, even if
the borrows it held have expired.

As a concrete example, we can consider Rust's `drain` interface. `Drain` is a
utility for efficiently performing bulk removal from the middle of a growable
array. Arrays require their elements to be stored contiguously, so removing
from the middle of one generally requires the elements after it to be
back-shifted to fill the hole. Doing this repeatedly is incredibly expensive,
so it's desirable to be able to defer the backshift until we are done removing
elements. Doing this means the array is in an unsound state while the
removals are happening.

One solution to this problem is to require the removals to be done in an
atomic fashion. For instance, if `drain` required a destination buffer to be
passed to it, then it could copy all the elements at once and back-shift at the
end of the function call. To the caller of `drain`, the array would appear to
always be in a consistent state. However such an interface is another example
of taking too much control from the user. They may not want to copy the elements
anywhere, but instead want to destroy them right away.

Instead, `drain` is implemented as an iterator. Elements are removed one at a
time, allowing the user to decide what is done with them without any need for
temporary allocations. However this means that we need to worry about the user
observing this inconsistent state, and how to clean it up. At first blush, the
problem seems trivial for Rust to solve. Drain is mutating the array, so it
contains a mutable reference to the array. That means the array is inaccessible
through any interface but the iterator itself while it exists. The backshift can
then be done in the iterator's destructor, which is exactly when the borrow it
holds expires. Perfect!

```rust
// A growable array with 5 numbers
let mut arr = vec![0, 1, 2, 3, 4];

// Drain out elements 1 to 3 (exclusive).
// The result of `drain` is an iterator
// that we pass to the for loop to drive.
for x in arr.drain(1..3) {
    // arr is statically inaccessible here
    println!("{}", x);
}
// backshifting is performed once here
// arr is now accessible again

// 1 and 2 are now gone
assert_eq!(arr, vec![0, 3, 4]);
```

Unfortunately, the soundness of this design relies on the user of our interface
allowing the destructor to run. No reasonable code would ever *not* run the
destructor, but since one can violate memory safety by accessing these empty
indices, we cannot tolerate the possibility.

Thankfully, all is not lost. The solution to our problem is in fact quite simple.
Rather than relying on the destructor to put the array in a *sound* state,
we will put the array into an incorrect but otherwise sound state, and rely on
the destructor to put the array into the correct state. We call this strategy
*poisoning*. If the user of our interface prevents the destructor from running,
they'll get a poisoned array which will probably cause their program to behave
incorrectly, but be unable to violate memory safety.

In the case of `drain`, the poison is setting the length of the array to be zero.
The destructor in turn just sets the length to the correct value (which it would
have done anyway). So the overhead for this scheme is zeroing out a single
integer, which is completely negligible considering the operation we're performing.
The consequence of this poison is that all the elements in the array will be
lost if the destructor is leaked. There's a certain fairness to this: you leak me,
I leak you!

Not all interfaces have such a convenient poison though. If this is the case, one
may instead ensure some code executes by inverting the control. Instead of our
code having to execute in the user's function, we can require the user's code
to execute in ours. In the case of drain, we can require the user to pass a
function that will be passed a *pointer* to the iterator, preventing them from
gaining true ownership of the iterator. We can then guarantee that the iterator's
destructor always runs by dropping it in our own function. In fact, because we
always control the value, we don't even need to use a destructor to ensure the
cleanup code runs.

```rust
let mut arr = vec![0, 1, 2, 3, 4];

// Drain out elements 1 to 3 (exclusive).
// `drain` has no result, but instead passes a
// pointer to a Drain iterator that it owns.
arr.drain(1..3, |iter| {
    // arr is statically inaccessible here
    for x in iter {
        println!("{}", x);
    }
}); // backshifting is performed once here
// arr is now accessible again

// 1 and 2 are now gone
assert_eq!(arr, vec![0, 3, 4]);
```

This design is a bit less ergonomic and flexible, but it can easily cover the
common cases.







# Related Work

TODO: this whole section?

As has been noted, Rust's constituent parts aren't unique. Other languages have
consequently been built on the same or similar foundations. Of particular
interest is Cyclone, Alms, and Vault.



## Cyclone

Although Rust was not originally based on Cyclone, the version of Rust that
was stabilized can be seen as the direct descendant of the final version of
Cyclone. Most notably, the region analysis employed by Rust and Cyclone for
borrowed pointers is (as far as we can tell) identical. Where the two deviate
is in affine typing. Since Cyclone intended to be a drop-in replacement for C,
it was based largely around copy semantics, and not move semantics. However
near the end of its development Cyclone introduced affine unique and
reference-counted pointers in order to enable more flexible memory management.
These types were built into the language, and no mechanism was provided to mark
other types as affine. As such, affine typing couldn't be used as a mechanism to
manage access to data, because all other data was still freely copyable. Instead,
affine typing was used exclusively for allocation management.




## Alms

Alms has affine types, but exposes a more advanced mechanism than regions. It's
sufficient to implement regions as a library notion.



## Vault

Vault uses linear typing instead of affine typing.


[Cyclone]: http://www.cs.umd.edu/projects/cyclone/papers/cyclone-safety.pdf
[cyclone-regions]: http://www.cs.umd.edu/projects/cyclone/papers/cyclone-regions.pdf
[tofte-regions]: https://www.irisa.fr/prive/talpin/papers/ic97.pdf
[cyclone-existentials]: https://homes.cs.washington.edu/~djg/papers/exists_imp.pdf
[c-exploits]: TODO
[integer-turing]: TODO
[list fusion]: https://downloads.haskell.org/~ghc/7.0.1/docs/html/users_guide/rewrite-rules.html
[session types]: TODO
[sort-cliff]: TODO
[pivot-selection]: TODO
[no-array-bounds]: http://www.cs.bu.edu/~hwxi/academic/papers/pldi98.ps
[alms]: http://users.eecs.northwestern.edu/~jesse/pubs/dissertation/tov-dissertation-screen.pdf
[jdk-iter]: http://hg.openjdk.java.net/jdk7/jdk7/jdk/file/00cd9dc3c2b5/src/share/classes/java/util/ArrayList.java#l771
[coverity]: http://cacm.acm.org/magazines/2010/2/69354-a-few-billion-lines-of-code-later/fulltext
