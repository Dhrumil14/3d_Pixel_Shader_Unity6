namespace FuzzyGraph.Runtime
{
    public class MatchResult
    {
        public RuntimeRule rule;
        //public int score;
        public float scoreFloat;
        public bool hasMatch => rule != null;
    }
}