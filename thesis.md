# Titles

* You Can't Spell Trust Without Rust
* Shared Mutability Kills Freedom and Leads to Communism
* Designing APIs for Data-Trust


# Introduction

Rust is a new programming language with ambitious goals: in principle, Rust
is faster than C++ while being safer than Java, and easier to develop in than
both! In addition, Rust enables programmers to be fearless in the face of
concurrency and parallelism.

These are bold claims. What possible mechanism could enable this? Well, nothing
on its own is *truly* sufficient to make these claims. Rust largely just steals good
ideas from wherever it finds them. Piecewise, Rust isn't a particularly novel
language. This was in fact a specific design goal. Research is hard and slow.
As a whole, however, Rust has developed some interesting systems and insights.
The most important of these is *ownership*. Rust models data ownership in a
first-class manner unlike any other language in production today. To our knowledge,
the only language that comes even close to Rust in this regard is
[Cyclone][], which is no coincidence. Rust has sourced many great ideas from
Cyclone.

However Cyclone was largely trying to be as close as possible to C. As such,
many aspects of ownership weren't as well integrated or fleshed out as in Rust,
as legacy constraints got in the way. Cyclone has also unfortunately been
officially abandoned, and is no longer maintained or supported. By contrast,
Rust 1.0 was released last year, and the language has been going strong ever
since.

Ownership is not obviously some wonderful benefit though. Before we dive into
what ownership is and what it gains us, we need to understand the problems
it attempts to address.




# Trusting Data

Programming is hard. \[citation needed\]

We focus on one particularly interesting aspect of programming: trusting data.
All programs require or expect data to have certain properties. This trust
is pervasive and extends from raw program inputs to temporaries. Although it
may not seem to be the case at first, many of our problems boil down to trust.
This trust has many aspects:

First, there is the *property* of the data that is trusted. The simplest form of
trust is trusting that certain values don't occur. One can usually safely assume
a boolean does not ever contain the value `FileNotFound`. A more complex form of
trust is trusting that separate pieces of data agree. We expect array indices to be in
bounds, caches to be consistent with cached data, and dereferenced pointers to
point to allocated memory. Trust may also have a probabilistic nature. One may expect that
inputs are usually small or mostly duplicates.

Second, there is the *justification* of the trust. At one extreme, one may simply
*blindly* trust data. Indexing may be unchecked, and strings may be assumed to be
escaped. At the other extreme, one can *validate* or *correct* data at runtime.
Indexing may be checked, and strings may be unconditionally escaped.
Somewhere in-between these two extremes, one may choose to validate data through
static analysis or by design. Type checking ensures that booleans are not FileNotFound,
and normalized databases ensure that there is a single source of truth for each
fact. Of course, it is also possible to *accidentally* trust data by making
mistakes or misunderstanding the data. For instance, one may accidentally be
relying on strings to be ASCII by normalizing them with naive case-folding.

Note: this next one is iffy -- it's kind've coupled with 2 and 4. Also, focuses on
*code* trust more?

Third, there is the *who* to trust (scope of trust?). We generally trust our
hardware and languages to do exactly what they are told to do. When calling out
to a particular subroutine, it may also be reasonable to trust that subroutine
to be well-behaved. However when involving arbitrary third parties, one must
seriously consider whether to trust them. At a base level, a function must
decide whether to trust its caller. In generic contexts (such as when working
with interfaces or closures), one must also decide whether they trust the
generic code that they invoke. For instance, does one trust a comparison function
to be total, or even consistent?

Fourth and finally, there is the *consequences* of the trust; what happens if trust
is violated? If trust is violated an application could perform slightly worse,
produce nonsensical output, crash, or compromise the system it's running on.
The consequences of an assumption can easily shape whether that assumption is
made at all. Certainly, leaving the system vulnerable is not something to be
taken lightly.

We consider three major approaches to trust in the programming landscape:
trusting, suspicious, and paranoid.
No language uses just one strategy. Rather, most rely on a hybrid to balance
ergonomics, control, and safety. However many languages clearly favour some
approaches over others.




## Blind Trust

At one extreme, we have unconditional trust with little justification.

First and foremost, a trusting interface
is simply the easiest to *implement*. The implementor doesn't need to concern
themselves with corner cases because they are simply assumed to not occur. This
in turn give significant control to the user of the interface. The user doesn't
need to worry about the interface checking or mangling inputs. It's up
to them to figure out how correct usage is ensured.

Trusting interfaces are also,
in principle, ergonomic to work with. In particular one is allowed to try to use
the interface in whatever manner they please. This enables programs to be
transformed in a more continuous manner. Intermediate designs may be incorrect
in various ways, but if one is only interested in exploring a certain aspect
of the program that doesn't depend on the incorrect parts, they are free to do so.

Blind trust can be found in relatively small and local details like unchecked
indexing as well as massive and pervasive ones like manual memory management.

The uncontested champion of this approach is C. In particular, its notion of
*Undefined Behaviour* is exactly blind trust. C programs are expected to uphold
several non-trivial properties, and the C standard simply declares that if those
properties *don't* hold, the program is *undefined*. But here we see the
significant drawback of trusting interfaces. Breaking C's trust in this way has
dire consequences; the compiler is free to misoptimize the program in arbitrary
ways, leading to memory corruption bugs and high severity vulnerabilities.

This is far from an academic concern:
exploits deriving from C's pervasive unsafety [are bountiful][c-exploits].
Modern compilers try to give a helping hand with debug assertions and static
analysis, but blind trust is evidently too deeply ingrained into these languages.
Programs written in these languages continue to be exploited, and no end to
this is in sight.

The control that C's trusting design provides is highly coveted by many programmers.
Operating systems, web browsers, game engines, and other widely used pieces of
software continue to be primarily developed in C(++) because of the perceived
benefits of this control. Performance is perhaps the most well-understood benefit
of control, but it can also be necessary for correctness in the case of hardware
interfaces. This control is sufficiently important to many developers to the extent
that safer languages *without* it are simply irrelevant.




## Paranoia

At the other extreme of the spectrum we find paranoia. Paranoid designs
represent a distrust so deep that things must be taken away so as to eliminate
the problem *a priori*. There are two major families of paranoid practices:
omissions and static checking.

Omissions represent pieces of functionality that could have been provided or
used, but were deemed too error-prone. The much-maligned `goto` is perhaps
the most obvious instance of a paranoid omission, but it's not the most
interesting. The most interesting omission is the ability to manually free memory
which all garbage collected languages effectively reject. Some less popular
examples include always-nullable pointers (Haskell, Swift?, Rust),
concurrency (JavaScript), and side-effects (pure functional programming).

Static checking consists of verifying a program has certain properties at
compile-time. Static typing is the most well-accepted of these practices,
requiring every piece of data in the program to have a statically known type.
Various static lints for dubious behaviours fall into this category, including lints
for code style. Static paranoia also includes more exotic systems like
dependent-typing, which expresses requirements on runtime values (such as `x < y`)
at the type level.

The primary benefit of paranoid practices is maximum safety. Ideally, a paranoid
solution doesn't just handle a problem, it *eliminates* that problem. For instance,
taking away memory freeing completely eliminates the use-after-free, because there
is no after free (garbage collection being "only" an optimization). Similarly, a
lack of concurrency eliminates race conditions, because it's impossible to race.
Lints may completely eliminate specific mistakes, or simply reduce their
probability by catching common or obvious instances. Dependent typing can
prove that an index is in bounds, eliminating the need to check.

The cost of this safety is control. Paranoid practices point to the pervasive
problems that control leads to, and declare that this
is why we can't have nice things. It's worth noting that this loss of control
does not necessarily imply a loss in performance. In fact, quite the opposite
can be true: an optimizing compiler can use the fact that certain things are
impossible to produce more efficient programs. However paranoid practices do
generally take away a programmer's ability to directly construct an optimized
implementation. Instead one must carefully craft their program so that it
happens to be optimized in the desired manner. In some cases this may be
impossible.

The ergonomic impact of paranoid practices is a tricky subject. For the most part,
paranoid practices err on the side of producing false negatives. Better to
eliminate some good programs than allow bad programs to exist! This can lead to
frustration if one wishes to produce a program they believe to be a false
negative.

Omissions are generally much more well-accepted in this regard, particularly
when an alternative is provided that handles common cases. The
absence of manual free is quite popular because freeing memory is purely annoying
book-keeping. Freeing memory has no inherent semantic value, it's just necessary
to avoid exhausting system resources. The fact that garbage collection just
magically frees memory for you is pretty popular, as evidenced by its dominance
of the programming language landscape (C and C++ being notable defectors).
However some omissions can be too large to bear. Few systems are designed in
a pure-functional manner.

Static checking, on the other hand, is much more maligned. It's easy to forgive
an omission, particularly if one isn't even aware that an omission occurred (how many
programmers are even aware of goto these days?). Static checks on the other hand
are active and in the programmer's face. They may continuously nag the programmer
to do a better job, or even prevent the program from building altogether. Static
typing, one of the less controversial strategies, is rejected by many popular
languages (JavaScript, Python, Ruby). Dependent types struggle to find any
mainstream usage at all. These practices can also harm the ability to continuously
transform a program, forcing the programmer to prove that everything is correct
before allowing any code to run at all.

However in all cases, embracing paranoia can be liberating. Once a paranoid
practice is in place, one never needs to worry about the problems it addresses
again. If one collects their own rainwater, who cares what's being put in the
water supply?





## Suspicion

Finally we have the position of compromise: the suspicious practices. A suspicious
design often looks and acts a lot like a trusting design, but with one caveat: it
actually checks at runtime. The suspicious stance is that some baseline level of
safety is important, but categorically eliminating an error with a paranoid practice
is impractical. Suspicious practices can skew to be implicit or explicit, in an
attempt to fine-tune the tradeoffs.

In languages where pointers are nullable by default, it's common for all dereferences
to silently and implicitly check for `null`. This may cause the program to completely
crash or trigger unwinding (an exception in many languages). This allows the programmer
to write the program in a trusting way without worrying about the associated danger.

Other interfaces may require the author to explicitly acknowledge invalid cases.
For instance, an API may only provide access to its data through callbacks which it
invokes when the data is specifically correct or incorrect. This approach is often
more general, as it can be wrapped to provide the implicit form. Requiring
errors to be handled gives more control to the user and can improve the
clarity of code by reducing implicit control-flow. But this comes at
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
variety, is that they do little for actual program *correctness*. They make sure
that the program doesn't do arbitrary unpredictable with bad data, usually by
reliably crashing the program. This can be great for reproducing and fixing bugs,
but a crash is still a crash to the end user. This can be especially problematic
for critical systems, where a crash is essentially a critical vulnerability.

Suspicious solutions also often have the worst-in-class performance properties
of the three solutions. Trusting solutions let the programmer do whatever they
please while still aggressively optimizing. Paranoid solutions in turn give the
compiler and programmer alike rich information to optimize the program with
soundly. However a suspicious solution gets to assume little, and must bloat up
the program with runtime checks which further inhibit other optimizations.
That said, a good optimizing compiler can completely eliminate this gap. Bounds
checks in particular can be completely eliminated in common cases.










# Ownership

Rust tries to be a practical language. It understands that each perspective has
advantages and drawbacks, and tries to pick the best tool for each job. From each
perspective, Rust takes one key insight. From the blind-trust perspective we embrace
that control is incredibly important. Rust wants to be used in all the places where
C and C++ are used today, and being able to manually manage memory is a critical
aspect of that. From the paranoid perspective we embrace that completely
eliminating errors is great. Humans are fallible and get tired, but a good compiler
never rests and always has our back. From the suspicious perspective, we embrace
that compromises must be made for ergonomics and safety.

Part of Rust's solution is then simply taking our favourite solutions for
each specific problem: static types, runtime bounds checks, no nulls, wrapping
arithmetic, and so on. However Rust has one very large holistic solution to
many problems, and it's what seperates it from most other languages: ownership.
The ownership model has two major aspects: controlling where and when data lives;
and controlling where and when mutation can occur. These aspects are governed by
two major features: affine types and regions.





## Affine Types

At a base level, Rust manages data ownership with an *affine type system*. The
literature often describes affine types as being usable *at most once*, but from
Rust's perspective affine typing primarily means values are *uniquely owned*.

If a variable stores a collection, passing it to a function by-value or
assigning it to another variable transfers ownership of the value to the new
location. The new location gains access to the value, and the old location loses
access. Whoever owns the value knows that it is the only location
in existence that can possibly talk about the contents of the collection.
This allows the owner of the collection to soundly *trust* the
collection. Any properties it observes and wishes to rely on will not be changed
by some other piece of code without its permission. Perhaps more importantly,
the owner of the collection knows that it can due whatever it pleases with the
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
an invalidated value. The most obvious applications of affine typing are with various
forms of transient resources: threads, connections, files, allocations, and so on.

However it turns out that a surprising number of problems can be reduced to a
use-after problem. For instance, many APIs require some sequence of steps to
be executed in a certain order. This can be encoded quite easily using affine
types:

```rust
fn first() -> First;
fn second(First) -> Second;
fn third(Second) -> Third;
fn alternative(First) -> Alternative;
```

Using affine types, valid control flow can be modeled at the type level to statically
ensure correct usage. This can be done with a light hand, or a heavy hand.
At the light end one can use it to hint at correct usage or avoid obvious errors.
At the heavy end, one can effectively push the entire program into the type system, as is
the case for *[session types][]*.

It should be noted that affine typing isn't mandatory. For many types, like
booleans and integers, unique ownership doesn't make sense or isn't important.
Such type can opt into the Copy kind (an empty interface). Copy types behave
like any other value with one simple caveat: when they're moved, the old copy
of the value is still valid.

Copy semantics can have surprising consequences though.
For instance, it may be reasonable to implement Copy for a random number
generator (their internal state is generally just some integers). It then
becomes possible to accidentally copy the generator, causing the same
number to be yielded repeatedly. For this reason, some types which *could* be
copied safely don't opt into Copy. In this case, affine typing is used as a lint
against what is likely, but not necessarily, a mistake.





## Borrows and Regions

Affine types are all fine and good for some stuff, but if that's all Rust had,
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

However affine types really hit a wall when data wants to be *shared*. If
several pieces of code wish to concurrently read some data, we have a serious
issue. One solution is to simply *copy* the data to all the consumers. Each
has their own unique copy to work with, and everyone's happy.

However, even
if we're ignoring the performance aspect of this strategy (which is non-trivial),
it may simply not make sense. If the underlying resource to share is truly affine,
then there may be *no* way to copy the data in a semantic-preserving way. For
instance, one cannot just blindly copy a file handle.

At the end of the day, having only values everywhere is just dang *impractical*.
Rust is a practical language, so Rust has a solution: pointers! Unfortunately,
pointers unleash a fresh new hell of errors for us to make. Affine types "solved"
use-after errors for us, but pointers bring them back and make them *far* worse.
The fact that data has been moved or destroyed says nothing of the state of
pointers to it. As C has demonstrated since its inception, pointers are all too
happy to let us view data that might be destroyed or otherwise invalid.

Garbage collection solves this problem for allocations, but does nothing to
prevent trying to use an otherwise invalidated value, such as a closed file.
Rust's solution to this problem is Cyclone's most significant contribution to
the language: [regions][cyclone-regions].

Like affine types, regions are something well established in both theory and
implementation, but with little mainstream usage. Although Rust primarily steals
them from Cyclone, they were first [described by Tofte and Talpin][tofte-regions]
and used in an implementation of ML. That said, Cyclone's implementation of the scheme
is most immediately recognizable to a Rust programmer.

The heart of a region system is that pointers are associated with
the region of the program that they're valid for, and the compiler ensures that
pointers don't escape their region. This is done entirely at compile time, and
has no runtime component.

For Rust, these regions correspond to lexical scopes, which are roughly speaking
pairs of matching braces. Rust calls these regions *lifetimes*. The restriction to
lexical scopes is not fundamental, and was simply easier to implement for the
1.0 release. It is however sufficient for most purposes.

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
this at runtime. However in Rust, this is simply not a concern:
it's statically impossible. Closing the file destroys it, and that means all
pointers must be gone.

Unfortunately, this alone does nothing for finer-grained data invalidation. For
instance, what if we have a pointer to a growable array, as well
as a pointer *into* the array? If the array can be told to `pop` an element through a
pointer, then the element can become invalidated. There are several ways we could
approach this problem:

The most extreme solution is to simply forbid internal pointers. Then we never
have to worry about them being invalidated. Unfortunately this throws away a
ton of the value of pointers. Interior pointers are really useful!

Another way is to teach the region system about this data structure in
a deep way. Teach it that the pointer points to some internal data of the array,
and that the `pop` operation moves that data. This of course raises the
question of granularity: does this system know about individual elements of the
array, or does it consider all of the elements in the stack to be some opaque blob?
If the former, does it allow us to pop the array if we don't have a pointer to
the last element? Going down this road quickly leads to a very complicated
type system, or just tracking these properties at runtime. Neither is desirable.

Yet another way is to treat all pointers into the array as pointers *to*
the array, and simply forbidding mutation through pointers. All mutating operations
could require by-value access, which could be done with borrow-threading.
This is unfortunate because we were trying to avoid borrow-threading by introducing
pointers in the first place. But hey, at least we can share data immutably,
which is still a definite win.

Rust basically takes this last approach, but in order to avoid the annoying pain of
threading borrows, it includes two different *kinds* of pointer:
*mutable references*, and *shared references*, denoted `&mut` and `&`
respectively. Shared references are exactly as we described: they can be
freely aliased, but only allow you to read the data they point to. Mutable
references on the other hand must be unique, but enable mutation of the data
they point to. This means that taking a mutable reference to some data is like moving
it, but then having the compiler automatically insert all the threading junk
to move it back into place when the mutable reference is gone (of course, the
compiler does not actually move the data around when you take a mutable
reference).




## Mutable ^ Shared

This is Rust's most critical perspective on ownership: mutation is mutually
exclusive with sharing. In order to get the most out of this perspective, Rust
also doesn't allow mutability to be declared at the type level. That is, a struct's
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

In particular, this eliminates a particularly pernicious kind of bug: *view
invalidation*. This is a problem that almost every language struggles with. Someone
takes a view into some data (a pointer and possible additional state), and then
someone else mutates the data causing the view to become invalid. The classic
example of view invalidation is *iterator invalidation*: someone trying to
mutate a collection while it's being iterated. There are some ways to do this
safely, but even if it's safe, it's likely a programming error.

For instance, consider the following program:

```rust
fn main() {
    let mut data = vec![1, 2, 3, 4, 5, 6];
    for x in &data {
        data.push(2 * x);
    }
}
```

What exactly the programmer's intent was here was unclear, and what exactly
will happen if this were allowed to compile is even more unclear. If the
iterator is C-like and stores a pointer directly into the array, then this code
will cause a use-after-free. Eventually the array will run out of memory and
have to reallocate, at which point, the iterator will point to free'd memory.
If the iterator is more conservative and instead points at the growable array
itself while holding an index into the array, then the iterator will be robust
to reallocations. However this code will still be an infinite loop.

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
forbidden by Rust's scheme. As such, everything in Rust is threadsafe by default.
However concurrent algorithms and data structures are rife with aliasing and
mutability. Mutexes exist *precisely* to enable aliasing and mutation in a
controlled manner.

As a result, although inherited mutability is the default way to do things in
Rust, it is not the only way. A few key types provide *interior mutability*,
which enable their data to be mutated through shared references, with some
runtime mechanism to ensure that mutable references aren't aliased. The most
obvious example of this is exactly the standard library's Mutex type, which
allows a `&Mutex<T>` to become an `&mut T` by acquiring its lock.

However this is useful pattern even outside of a concurrent context, and some
single-threaded equivalents also exist. These types are however prevented from
being used in a concurrent context precisely because they aren't threadsafe.
(Is this worth going into? Seems like a digression)







# Unsafe Rust

(this needs to be rewritten because it was based on the old stuff. I think I
might want to hoist a discussion of safety to be closer to the data trust stuff?
Defining memory safety, type safety, and so on. Basically a better version of
my blog post)

We originally separated all programming languages into two major categories:
those that are safe, and those that are unsafe. This is of course a ridiculous
over-simplification. In fact, basically *every* language has unsafe bits that
make the language totally unsound. The most fundamental of these is quite
simple: talking to C. C is the lingua-franca of the programming world. All
major operating systems and many major libraries primarily expose a C interface.
Any language that wants to integrate with these systems must therefore learn
how to talk to C. Because C is *definitely* unsafe and can do just about anything,
to your program, these languages then become transitively unsafe.

Rust is no different, but it does embrace this reality a little more than most
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
languages, if you need to do something very low level (for performance, control,
or any other reason) the general solution to this is "use C".

This comes with a very significant cognitive overhead. Your application now has
its logic spread across two completely different languages with different
semantics, runtimes, and behaviors. If the safe language is what your team
primarily works in, it's unlikely that a significant percentage of the team is
qualified to actively maintain the C components.

It also incurs non-trivial runtime overhead. Data must often be reformatted at
the language boundary, and this boundary is usually an opaque box for either
language's optimizer.

Finally, falling back to C is simply a *huge* jump in unsafety, from "totally
safe" to "pervasively unsafe".

Unsafe Rust largely avoids these issues with one simple fact:
it's just a superset of Safe Rust. Lifetimes, Affine Types, and everything else
that helps you write good Rust programs are still working exactly as before.
You're just allowed to do a few extra things that are unsafe. As a result,
there's no unnecessary runtime or semantic overhead for using Unsafe Rust.

Although of course you do need to understand how to manually uphold Safe Rust's various
guarantees, which is non-trivial. However even this is a better situation than
using C, because the unsafety is generally much more modular. For instance, if
you use Unsafe Rust to index into an array in an unchecked manner, you don't
suddenly need to worry about the array being null, dangling, or containing
uninitialized memory. All you need to worry about is if the index is actually
in bounds. You know everything else is still normal.

In addition, Unsafe Rust doesn't require any kind of complicated foreign function interface.
It can be written inline with Safe Rust on demand. Rust's only requirement is that you
write the word `unsafe` *somewhere* to indicate that you understand that what
you're doing is unsafe. Since unsafety is explicitly denoted in this manner, it
also enables it to be detected and linted against if desired.

Rust's standard library (which is written entirely in Rust) makes copious use of
Unsafe Rust internally. Most fundamentally,
Unsafe Rust is necessary to provide various operating system APIs because those are
written in C, and only Unsafe Rust can talk to C. However Unsafe Rust is also used in
various places to implement core abstractions like mutexes and growable arrays.

It's important to note that the fact that these APIs unsafe code is entirely an
implementation detail to those using the standard library. All the unsafety is
wrapped up in *safe abstractions*. These abstractions serve
two masters: the consumer of the API, and the producer of the API. The benefit to
consumers of an API is fairly straight-forward: they can
rest easy knowing that if something terrible happens, it probably wasn't their
fault. For producers of the API, these safe abstractions mark a clear boundary
for the unsafety they need to worry about.

Unsafe code can be quite difficult because it often
relies on stateful invariants. For instance, the capacity of a growable array
is a piece of state that unsafe code must trust. However within the array's
privacy boundary, this state can be arbitrarily manipulated by anyone. The
abstraction boundary is often exactly where privacy kicks in, preventing
consumers of the API from doing arbitrarily bad things to the state unsafe
code relies on.

This thesis focuses primarily on these safe abstractions. A good safe abstraction
must have many properties:

* Safety: Using the abstraction inappropriately cannot violate Rust's safety guarantees
* Efficiency: Ideally, an abstraction is *zero cost*, meaning it is as efficient
  at the task it is designed to solve as an unabstracted solution (with a decent
  optimizing compiler).
* Usability: A good abstraction should be more convenient and easy to understand than
  the code it's wrapping.

It would be *excellent* if the implementation was also completely safe, but we
do not consider this a critical requirement.

It should be noted that Rust's reliance on safe abstractions is, in some sense,
unfortunate. For one, it makes reasoning about the performance characteristics
of a program much more difficult. It has also left Rust's unoptimized
performance in a rather atrocious state. It is not uncommon for a newcomer to
the language to express shock that a Rust program is several times slower than
an equivalent Python program, only to learn that enabling optimizations makes
the Rust program several times faster than Python.

However it is our opinion that this is simply fundamental to providing a
programming environment that is safe, efficient, and usable.








# Designing APIs for Trust

(Haven't looked at this in a while, might be really out of date)

It has been our experience that almost everything you want to express at a high level
can be safely, efficiently, and usably expressed in an ownership-oriented system.
However this does *not* mean that you can express it however you please!
In order to achieve all of these goals, the API itself must model and work
around the issue of data trust. If the API does not correctly work with trust,
then it will either be unsafe (in which case there is an aspect of blind trust),
inefficient (in which case there is an aspect of suspicion), or unusable (in which
case trust was achieved in an annoying or unintuitive way).

Consider a relatively simple problem: indexing into arrays. As we have noted,
indexing out of bounds is a fundamental memory safety violation. There are three
major strategies for indexing: blindly trust the value, blindly check the value, or
statically prove the value is valid.

To recap, always checking the value at runtime is the most common strategy,
because it's safe, easy to use, and easy to implement. Blindly trusting the
value is of course unsafe, but
generally more efficient. Statically validating the value is in principle the best
of both worlds: maximally efficient, and even safer than the checked version
because it's guaranteed to succeed at runtime. However statically proving all
indexing is in bounds suffers from the usability perspective. Using dependent
types, it *is* possible to statically verify some bounds checking, but it takes
a pretty significant extension to most languages to support this.

Due to the significant complexity of dependent types, Rust opted for the runtime
checking solution. Interestingly, even though Rust programs are
*semantically* unconditionally performing bounds checks, we don't unconditionally
lose performance.

First off, these bounds checks are by definition trivially predictable in a
correct program. So the overhead at the hardware level is quite small. That said,
having to do the checks at all s the worst-case. A good optimizing compiler
(like LLVM) can optimize away many bounds checks. For instance, the following
code doesn't actually perform any bounds checks when optimized, because LLVM can
see that the way the indices are generated trivially satisfies the bounds
checking.

```rust
let mut x = 0;
for i in 0 .. arr.len() {
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
to magically figure out what we're doing: We need to actually not do bounds
checking. One solution is to provide an escape hatch to the safe interface:
provide a raw unchecked version of indexing. However opting into this is an
unfortunate trade to make: guaranteed unchecked iteration puts memory safety at
risk.

Thankfully, this is a false dichotomy. This code is hard to optimize safely
because we've pushed too much of the problem at hand to the user of the array.
They need to figure out how to generate the access pattern, and we in turn can't
trust it. If the array itself handles generating the access pattern *and*
acquiring the elements, then all the bounds checks can be eliminated at the
source level in a way that's safe to the end-user. This is handled by a tried
and true approach: iterators.

```rust
let mut sum = 0;
for &x in arr.iter() {
    sum += x;
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
is incredibly common, and is well worth the specialization. But if the
user wants binary search an array without bounds checks, iterators do them no
good.

This is why Rust also provides a raw unchecked indexing API. If users have a
special case and really need to optimize it to death, they can drop down to
the raw API and regain full control. In the case of arrays, the raw API is
trivial to provide and obvious, so there is little worry of the maintenance burden
or unnecessarily exposing implementation details. This isn't true for all
interfaces (what's the raw API for searching an abstract ordered map?).




It turns out that ownership provides us with powerful tools for manufacturing
data trust. For instance, escape analysis is notable in garbage collected
languages for its ability to avoid allocating memory on the heap at all by proving
that data does not escape some region of the code. Rust's lifetimes are exactly
for proving that data does not escape some region. However, instead of a failed analysis
producing a less efficient program, it prevents the program from compiling *at all*.
Rust is simply a garbage collected language with perfect escape analysis,
allowing the implementors to not implement the actual garbage collector at all.

Affine types in turn give us powerful aliasing guarantees. An iterator cannot
be invalidated because aliasing and mutation is a compiler error, and not simply
the optimizer's slow path.






# Entry API

(not finished)

As we have noted, abstractions are not a panacea. A bad abstraction can end up
producing more work the designers and users of the abstraction. A notable example
of this was the old `find_or` API for maps. The motivation for the API was simple:
maps are often used as key accumulators, requiring different logic to be performed
the first time a key is encountered. This is of course true in general. The map
data structure must do something special when inserting a genuinely new key,
instead of just replacing one. However in the case of accumulators, the *user*
of the map needs to do something special.

Consider using a map to count the number of occurrences of different strings. The
first time a key is found, we would like to simply insert the value `1`. However
ever subsequent insertion, we instead want to increment the value stored under
the key. This is fairly easy to implement using standard map APIs:

```rust
if let Some(count) = map.get_mut(&key) {
    *count += 1;
} else {
    map.insert(key, 1);
}
```

But this design has a frustrating performance issue: in the `else`
case, we end up doing two lookups in the map. The standard library's initial
solution to this problem was to expose a new method that allowed the user to
specify a default value, `find_or_insert(key, default_value)`. This handles
the simple counter case perfectly well:

```rust
*map.find_or_insert(&key, 0) += 1;
```

But it may be the case the the value is too expensive (or incorrect) to compute
unconditionally. To address this, a new method was added that allows a function
to be passed that will compute the value by-need, `find_or_insert_with(key, default_function)`.

From there it got ever more out of control. It may be the case that the operation
you want to perform after the insertion depends on whether the key was new or not,
and this design doesn't expose that information.

Eventually, this culminated in the following monstrosity (updated to modern Rust):

```rust
fn find_with_or_insert_with<A, F, NF>(&mut self, k: K, a: A, found: F, not_found: NF) -> &mut V
    where F: FnOnce(&K, &mut V, A)
          FN: FnOnce(&K, A) -> V
```

`find_with_or_insert_with` takes two functions: one to execute if the key existed, and one
to execute if the key didn't exist. But because of this design, we end up with this curious
`A` type mixed in. What is the purpose of this value? Well, normally if you wanted a
function to use some local data, you would use a closure. Unfortunately, two closures can't
close over the same value if it's affine. In this case, we know only one of the closures
will be executed, so we can soundly close over the same piece of data twice. In order
to encode this, we have the user manually pass in the state to be closed over.

What a nightmare!

It's easy to conclude that this is, to some extent, ownership's fault. Certainly
the closure trick would be unnecessary in a garbage-collected language. However
this is actually just a bad abstraction. We instead replaced this API with a
completely different one: the `entry` API.

Instead of a handful of increasingly inscrutable methods to achieve this functionality,
we only have one, `entry(key)`






# Hacking Dependent Types on top of Rust

Given the array iteration example, one might wonder if it's sufficient for the
array to simply provide the indices. This would be a more composable API with
a reduced implementation burden. Perhaps this API could be used something like this:

```
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
tampered with.

However this is still insufficient unless the *origin* of
these values cannot be verified. Given two arrays, it mustn't be possible to index
one using the indices of the other:

```
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

```
let i = arr.indices().next().unwrap();
arr.pop();
// index arr with an outdated index
let x = arr[i];
```

By pure accident, Rust provides enough tools to solve
this problem. It turns out that lifetimes in conjunction with some other features
are sufficient to construct a limited form of dependent typing. We won't lie:
this is an ugly hack, and we don't expect to use it in any kind of regular way.
Still, it's an option.

In order to encode sound unchecked indexing, we need a way for types to talk about
particular instances of other types. In this case, we specifically need a way
to talk about the relationship between a particular array, and the values of
indices. Rust's lifetime system, it turns out, gives us exactly that. Every
instance of a value that contains a lifetime (e.g. a pointer) is referring to
some particular region of code. Further, code can require that two lifetimes
satisfy a particular relationship (typically, that one outlives the other).

The basic idea is then as follows: associate an array and its indices with
a particular region of code. Unchecked indexing then simply requires that the
input array and index are associated with the same region.
However care must be taken, as Rust was not designed to support this. In
particular, the borrow checker is a constraint solver that will attempt do
everything in its power to make code pass type checking. As such, if it sees
a constraint that two lifetimes must be equal it may expand their scopes in
order to satisfy this constraint. Since we're trying to explicitly use equality
constraints to prevent certain programs from compiling, this puts us at odds
with the compiler.

In order to accomplish our goal, we need to construct a black box that the
borrow checker can't penetrate. This involves two steps: disabling lifetime variance,
and creating an inaccessible scope. Disabling variance is relatively straight
forward. Several generic types disable variance in order to keep Rust sound.
Getting into the details of this is fairly involved, so for now we will just
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
sufficiently common requirement in Rust that the language provides a primitive
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
to a function is a "fresh" lifetime, and can only unify them if that function
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
            // println!("{}", arr2.get(i));
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




# jdjjdjjdjdjjdjjdjjdjdjdjdjdd







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
