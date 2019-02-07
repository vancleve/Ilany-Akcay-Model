using StatsBase
using Plots

#Node structure represents individuals in population
mutable struct Node
    strategy::Int8 #1 if cooperator, 0 if defector
    payoff::Float64
    fitness::Float64
    ID::Int64
end

#globals structure exists in one instance; contains all universal variables
mutable struct globals
    popSize::Int64 #number of individuals in population
    edgeMatrix::Array{Int64, 2} #matrix of binary Ints; 1 where connection between row and col index is present
    meanCoopRatio::Float64 #summed over 500 generations, then calculated after core function
    population::Array{Node, 1} #contains 100 Node structs
    numInitialCoops::Int64 #number of cooperators at initialization of globals; used once per run
    numInitEdges::Int64 #number of edges in network at initialization of globals; used once per run
    numGens::Int64 #generations per run; currently last 400 add into meanCoopRatio
    pN::Float64 #probability that infant connects to parent's neighbor
    pR::Float64 #probability that infant connects to random Node
    #pB is assumed to be 1 in this simulation
    benefit::Float64 #payoff to be distributed amongst cooperator's neighbors
    synergism::Float64 #payoff for mutual cooperators; inversely related to degrees
    cost::Float64 #payoff lost by cooperators
    delta::Float64 #strength of selection
    mu::Float64 #chance of strategy mutation in infant

    #generic constructor takes no parameters; uses same globals for each run
    #CHANGE VARIABLES HERE
    function globals()
        #basic variables for measurement
        popSize = 100
        meanCoopRatio = 0.0

        #initialization factors (may need to be adjusted)
        numInitialCoops = popSize/2
        numInitEdges = Int(round(1.5*popSize))

        #specific details of simulation
        numGens = 500
        pN = .4
        pR = .03
        benefit = 2.0
        synergism = 0.0
        cost = 0.5
        delta = 0.1
        mu = .001

        #defines population as a Node Array with 100 spots, then fills it with cooperators at beginning and defectors afterwards
        population = Array{Node, 1}(undef, 100)
        for(i) in 1:popSize
            population[i] = Node(0, 0, 1, i)
            if(numInitialCoops > 0)
                population[i].strategy = 1
                numInitialCoops -= 1
            end
        end

        #empties edgeMatrix, then finds pairs of distinct indices to connect
        edgeMatrix = zeros(Int64, popSize, popSize)
        for(i) in 1:numInitEdges
                firstID = Int(round(rand()*popSize+.5))
                secondID = firstID
                while(secondID == firstID)
                    secondID = Int(round(rand()*popSize+.5))
                    if(edgeMatrix[firstID, secondID] == 1 || edgeMatrix[secondID, firstID] ==1)
                        secondID = firstID
                        continue
                    end
                end
                edgeMatrix[firstID, secondID] = 1;
                edgeMatrix[secondID, firstID] = 1;
        end

        #constructs globals structure
        new(popSize, edgeMatrix, meanCoopRatio, population, numInitialCoops, numInitEdges, numGens, pN, pR, benefit, synergism, cost, delta, mu)
    end
end

#measurement function; name and contents regularly change
#CURRENTLY: counts cooperators and adds the frequency of cooperation to meanCoopRatio
function countCoops(over::globals)
    coopCount = 0.0
    for(i) in 1:over.popSize
        if(over.population[i].strategy == 1)
            coopCount += 1.0
        end
    end
    coopRatio = coopCount/over.popSize
    over.meanCoopRatio += coopRatio

    #vestigial bar chart formatting (may be used later)
    #=
    linkBars = bar(0:1:popSize, freqData)
    linkBars
    =#
end

#core function; conducts 100 birth-death events per generation with selection for high payoff
#accepts globals struct as a parameter
function runGens(over::globals)
    for(g) in 1:(over.numGens * over.popSize)

        #randomly selects a node to die and resets its connections, payoff and fitness
        spliceID = Int(round(rand()*over.popSize+.5))
        over.edgeMatrix[spliceID, :] .= 0
        over.edgeMatrix[:, spliceID] .= 0
        over.population[spliceID].payoff = 0
        over.population[spliceID].fitness = 1

        #calculates relative fitnesses of nodes, creates a weight vector, and samples a parent with selection weight
        fitSum = 0.0
        fitnesses = zeros(over.popSize)
        for(i) in 1:over.popSize
            fitSum += over.population[i].fitness
        end
        for(i) in 1:over.popSize
            fitnesses[i] = over.population[i].fitness/fitSum
        end
        fitWeights = weights(Array{Float64, 1}(fitnesses))
        momIndex = sample(1:over.popSize, fitWeights)

        #mutates 1 in 1000 infants, then connects infant to parent
        if(rand() > over.mu)
            over.population[spliceID].strategy = over.population[momIndex].strategy
        else
            over.population[spliceID].strategy = ((over.population[momIndex].strategy) * (-1)) + 1
        end
        over.edgeMatrix[spliceID, momIndex] = 1
        over.edgeMatrix[momIndex, spliceID] = 1

        #formation of edges from infant to various nodes following social inheritance
        for(i) in 1:over.popSize

            #identifies parent neighbors in population, then connects to neighbors with prob pN and strangers with prob pR
            momNeighbor = false
            if(over.edgeMatrix[momIndex, i] == 1)
                momNeighbor = true
            end
            if( i != spliceID && over.edgeMatrix[spliceID, i] == 0)
                if(momNeighbor && rand() < over.pN)
                    over.edgeMatrix[i, spliceID] = 1
                    over.edgeMatrix[spliceID, i] = 1
                elseif(!momNeighbor && rand() < over.pR)
                    over.edgeMatrix[i, spliceID] = 1
                    over.edgeMatrix[spliceID, i] = 1
                end
            end
        end

        #cooperation occurs at every cooperator node
        for(i) in 1:over.popSize
            if(over.population[i].strategy == 1)

                #counts degree of cooperator and mutual cooperators
                benCount = 0
                coopCount = 0
                for(ii) in 1:over.popSize
                    if(over.edgeMatrix[i, ii] == 1)
                        benCount+=1
                        if(over.population[ii].strategy == 1)
                            coopCount+=1
                        end
                    end
                end

                #initializes then fills arrays of indices of beneficiary neighbors and mutually cooperating neighbors
                beneficiaryNodes = collect(1:benCount)
                benCount = 1
                coopBeneficiaries = collect(1:coopCount)
                coopCount = 1
                for(ii) in 1:over.popSize
                    if(over.edgeMatrix[i, ii] == 1)
                        beneficiaryNodes[benCount] = ii
                        benCount += 1
                        if(over.population[ii].strategy == 1)
                            coopBeneficiaries[coopCount] = ii
                            coopCount+=1
                        end
                    end
                end

                #gives payoff to beneficiaries relative to degree of cooperator as well as synergistic benefits for mutual cooperators
                benCount -= 1
                coopCount -= 1
                for(b) in 1:(benCount)
                    over.population[beneficiaryNodes[b]].payoff += (over.benefit/(benCount))
                end
                for(c) in 1:(coopCount)
                    coopDegree = 0
                    for(cc) in 1:over.popSize
                        if(over.edgeMatrix[coopBeneficiaries[c], cc] == 1)
                            coopDegree += 1
                        end
                    end
                    over.population[coopBeneficiaries[c]].payoff += over.synergism/(coopDegree*(benCount))
                end

                #subtracts cost from identified cooperator node's payoff
                over.population[i].payoff -= over.cost
            end
        end

        #calculates fitnesses based on payoffs per Akcay then resets payoffs
        for(i) in 1:over.popSize
                over.population[i].fitness = (1.0 + over.delta) ^ over.population[i].payoff
                over.population[i].payoff = 0
        end

        #counts cooperators in last 400 generations after 100 birth-death events
        if((g > 100 * over.popSize) && (g % over.popSize == 0))
            countCoops(over)
        end
    end
end

#replicates data for 100 simulations
for(x) in 1:100

    #initializes globals structure with generic constructor
    overlord = globals()

    #clears memory of dead globals structures or nodes
    GC.gc()

    #checks efficiency of simulation while running it
    @time runGens(overlord)

    #divides meanCooperationRatio by last 400 generations to get a true mean, then outputs
    overlord.meanCoopRatio = overlord.meanCoopRatio/400.0
    println("Mean Cooperation Ratio: $(overlord.meanCoopRatio)")
end